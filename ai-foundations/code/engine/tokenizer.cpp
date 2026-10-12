#include "tokenizer.hpp"

#include <algorithm>
#include <limits>

namespace aif {

namespace {

enum class Cls { Letter, Number, Space, Other };

// The GPT-2 pattern needs Unicode classes. ASCII is classified exactly; elsewhere, common
// spaces, punctuation, symbols and digits are recognised and everything else counts as a letter.
Cls classify(uint32_t c) {
    if (c < 0x80) {
        if ((c | 0x20) >= 'a' && (c | 0x20) <= 'z') return Cls::Letter;
        if (c >= '0' && c <= '9') return Cls::Number;
        if (c == ' ' || (c >= 0x09 && c <= 0x0D) || (c >= 0x1C && c <= 0x1F))
            return Cls::Space;
        return Cls::Other;
    }
    if (c == 0x85 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 ||
        c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000)
        return Cls::Space;
    if (c == 0xB2 || c == 0xB3 || c == 0xB9 || (c >= 0xBC && c <= 0xBE) ||
        (c >= 0x660 && c <= 0x669) || (c >= 0x966 && c <= 0x96F) ||
        (c >= 0xFF10 && c <= 0xFF19))
        return Cls::Number;
    if ((c >= 0xA1 && c <= 0xBF && c != 0xAA && c != 0xB5 && c != 0xBA) || c == 0xD7 ||
        c == 0xF7 || (c >= 0x2010 && c <= 0x205E) || (c >= 0x20A0 && c <= 0x2BFF) ||
        (c >= 0x3001 && c <= 0x303F) || (c >= 0xFE30 && c <= 0xFE4F) ||
        (c >= 0xFF01 && c <= 0xFF0F) || (c >= 0x1F000 && c <= 0x1FAFF))
        return Cls::Other;
    return Cls::Letter;
}

struct CodePoints {
    std::vector<uint32_t> cp;
    std::vector<size_t> at;
};

CodePoints decodeUtf8(const std::string& s) {
    CodePoints out;
    for (size_t i = 0; i < s.size();) {
        unsigned char b = static_cast<unsigned char>(s[i]);
        int n = b < 0x80 ? 1 : (b >> 5) == 6 ? 2 : (b >> 4) == 14 ? 3 : (b >> 3) == 30 ? 4 : 1;
        if (i + n > s.size()) n = 1;
        uint32_t c = n == 1 ? b : b & (0x7F >> n);
        for (int k = 1; k < n; ++k)
            c = (c << 6) | (static_cast<unsigned char>(s[i + k]) & 0x3F);
        out.cp.push_back(c);
        out.at.push_back(i);
        i += n;
    }
    out.at.push_back(s.size());
    return out;
}

int hexValue(char c) {
    return c <= '9' ? c - '0' : (c | 0x20) - 'a' + 10;
}

}  // namespace

Tokenizer::Tokenizer(const json::Value& spec) : byteId_(256, -1) {
    for (const auto& hex : spec["tokens"].array()) {
        const std::string& h = hex.str();
        std::string bytes;
        for (size_t i = 0; i + 1 < h.size(); i += 2)
            bytes += static_cast<char>(hexValue(h[i]) * 16 + hexValue(h[i + 1]));
        tokens_.push_back(bytes);
    }
    for (int id = static_cast<int>(tokens_.size()) - 1; id >= 0; --id) {
        if (tokens_[id].size() == 1) byteId_[static_cast<unsigned char>(tokens_[id][0])] = id;
    }
    int rank = 0;
    for (const auto& m : spec["merges"].array()) {
        uint64_t key =
            (static_cast<uint64_t>(m[0].num()) << 32) | static_cast<uint32_t>(m[1].num());
        merges_[key] = {rank++, static_cast<int>(m[2].num())};
    }
    for (const auto& [name, id] : spec["special"].object())
        special_[name] = static_cast<int>(id.num());
    splitDigits_ = spec["split_digits"].boolean();
}

// snippet:begin pretokenise
void Tokenizer::pretokenise(const std::string& text, std::vector<std::string>& out) const {
    CodePoints t = decodeUtf8(text);
    std::vector<Cls> cls(t.cp.size());
    for (size_t i = 0; i < t.cp.size(); ++i) cls[i] = classify(t.cp[i]);
    auto emit = [&](size_t a, size_t b) {
        out.push_back(text.substr(t.at[a], t.at[b] - t.at[a]));
    };
    auto run = [&](size_t i, size_t end, Cls c) {
        while (i < end && cls[i] == c) ++i;
        return i;
    };
    auto segment = [&](size_t i, size_t end) {
        while (i < end) {
            if (t.cp[i] == '\'' && i + 1 < end) {
                uint32_t a = t.cp[i + 1], b = i + 2 < end ? t.cp[i + 2] : 0;
                if ((a == 'l' && b == 'l') || (a == 'v' && b == 'e') ||
                    (a == 'r' && b == 'e')) {
                    emit(i, i + 3);
                    i += 3;
                    continue;
                }
                if (a == 's' || a == 'd' || a == 'm' || a == 't') {
                    emit(i, i + 2);
                    i += 2;
                    continue;
                }
            }
            bool matched = false;
            for (Cls c : {Cls::Letter, Cls::Number, Cls::Other}) {
                size_t from = t.cp[i] == ' ' && i + 1 < end && cls[i + 1] == c ? i + 1 : i;
                if (cls[from] == c) {
                    size_t j = run(from, end, c);
                    emit(i, j);
                    i = j;
                    matched = true;
                    break;
                }
            }
            if (matched) continue;
            size_t j = run(i, end, Cls::Space);
            size_t stop = j < end && j - i >= 2 ? j - 1 : j;
            emit(i, stop);
            i = stop;
        }
    };
    size_t start = 0;
    for (size_t i = 0; i < t.cp.size(); ++i) {
        if (splitDigits_ && cls[i] == Cls::Number) {
            segment(start, i);
            emit(i, i + 1);
            start = i + 1;
        }
    }
    segment(start, t.cp.size());
}
// snippet:end pretokenise

// snippet:begin bpe
std::vector<int> Tokenizer::encodeChunk(const std::string& chunk) const {
    std::vector<int> ids;
    for (unsigned char b : chunk) {
        if (byteId_[b] >= 0) ids.push_back(byteId_[b]);
    }
    while (ids.size() > 1) {
        int bestRank = std::numeric_limits<int>::max(), merged = -1;
        uint64_t bestKey = 0;
        for (size_t i = 0; i + 1 < ids.size(); ++i) {
            uint64_t key =
                (static_cast<uint64_t>(ids[i]) << 32) | static_cast<uint32_t>(ids[i + 1]);
            auto it = merges_.find(key);
            if (it != merges_.end() && it->second.first < bestRank) {
                bestRank = it->second.first;
                merged = it->second.second;
                bestKey = key;
            }
        }
        if (merged < 0) break;
        std::vector<int> next;
        for (size_t i = 0; i < ids.size(); ++i) {
            uint64_t key = i + 1 < ids.size() ? (static_cast<uint64_t>(ids[i]) << 32) |
                                                    static_cast<uint32_t>(ids[i + 1])
                                              : 0;
            if (i + 1 < ids.size() && key == bestKey) {
                next.push_back(merged);
                ++i;
            } else {
                next.push_back(ids[i]);
            }
        }
        ids.swap(next);
    }
    return ids;
}
// snippet:end bpe

std::vector<int> Tokenizer::encode(const std::string& text) {
    std::vector<std::pair<std::string, int>> specials(special_.begin(), special_.end());
    std::sort(specials.begin(), specials.end(),
              [](const auto& a, const auto& b) { return a.first.size() > b.first.size(); });
    std::vector<int> out;
    std::vector<std::string> chunks;
    size_t start = 0;
    auto flush = [&](size_t end) {
        chunks.clear();
        pretokenise(text.substr(start, end - start), chunks);
        for (const auto& c : chunks) {
            auto it = cache_.find(c);
            if (it == cache_.end()) it = cache_.emplace(c, encodeChunk(c)).first;
            out.insert(out.end(), it->second.begin(), it->second.end());
        }
    };
    for (size_t i = 0; i < text.size(); ++i) {
        for (const auto& [name, id] : specials) {
            if (text.compare(i, name.size(), name) == 0) {
                flush(i);
                out.push_back(id);
                i += name.size() - 1;
                start = i + 1;
                break;
            }
        }
    }
    flush(text.size());
    return out;
}

std::string Tokenizer::decode(const std::vector<int>& ids) const {
    std::string out;
    for (int id : ids) out += tokens_.at(id);
    return out;
}

}  // namespace aif
