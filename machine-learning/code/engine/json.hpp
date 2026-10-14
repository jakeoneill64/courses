#pragma once

#include <cstdlib>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace aif::json {

struct Value;
using Array = std::vector<Value>;
using Object = std::map<std::string, Value, std::less<>>;

struct Value {
    std::variant<std::nullptr_t, bool, double, std::string, std::shared_ptr<Array>,
                 std::shared_ptr<Object>>
        v;

    const Value& operator[](std::string_view key) const {
        const auto& o = *std::get<std::shared_ptr<Object>>(v);
        auto it = o.find(key);
        if (it == o.end()) throw std::runtime_error("json: no key " + std::string(key));
        return it->second;
    }
    const Value& operator[](size_t i) const { return array().at(i); }
    const Array& array() const { return *std::get<std::shared_ptr<Array>>(v); }
    const Object& object() const { return *std::get<std::shared_ptr<Object>>(v); }
    const std::string& str() const { return std::get<std::string>(v); }
    double num() const { return std::get<double>(v); }
    bool boolean() const { return std::get<bool>(v); }
    size_t size() const { return array().size(); }
};

class Parser {
public:
    explicit Parser(std::string_view text) : s_(text) {}

    Value parse() {
        Value value = parseValue();
        skip();
        if (i_ != s_.size()) fail("trailing characters");
        return value;
    }

private:
    std::string_view s_;
    size_t i_ = 0;

    [[noreturn]] void fail(const char* what) const {
        throw std::runtime_error("json: " + std::string(what) + " at " + std::to_string(i_));
    }
    void skip() {
        while (i_ < s_.size() &&
               (s_[i_] == ' ' || s_[i_] == '\n' || s_[i_] == '\t' || s_[i_] == '\r'))
            ++i_;
    }
    bool take(char c) {
        skip();
        if (i_ < s_.size() && s_[i_] == c) {
            ++i_;
            return true;
        }
        return false;
    }

    Value parseValue() {
        skip();
        if (i_ >= s_.size()) fail("unexpected end");
        char c = s_[i_];
        if (c == '{') return parseObject();
        if (c == '[') return parseArray();
        if (c == '"') return Value{parseString()};
        if (s_.substr(i_, 4) == "true") return i_ += 4, Value{true};
        if (s_.substr(i_, 5) == "false") return i_ += 5, Value{false};
        if (s_.substr(i_, 4) == "null") return i_ += 4, Value{nullptr};
        char* end = nullptr;
        double d = std::strtod(s_.data() + i_, &end);
        if (end == s_.data() + i_) fail("bad value");
        i_ = static_cast<size_t>(end - s_.data());
        return Value{d};
    }

    Value parseObject() {
        auto object = std::make_shared<Object>();
        take('{');
        if (take('}')) return Value{object};
        do {
            skip();
            std::string key = parseString();
            if (!take(':')) fail("expected ':'");
            object->emplace(std::move(key), parseValue());
        } while (take(','));
        if (!take('}')) fail("expected '}'");
        return Value{object};
    }

    Value parseArray() {
        auto array = std::make_shared<Array>();
        take('[');
        if (take(']')) return Value{array};
        do {
            array->push_back(parseValue());
        } while (take(','));
        if (!take(']')) fail("expected ']'");
        return Value{array};
    }

    std::string parseString() {
        if (s_[i_] != '"') fail("expected string");
        ++i_;
        std::string out;
        while (i_ < s_.size() && s_[i_] != '"') {
            char c = s_[i_++];
            if (c != '\\') {
                out += c;
                continue;
            }
            char e = s_[i_++];
            switch (e) {
                case 'n': out += '\n'; break;
                case 't': out += '\t'; break;
                case 'r': out += '\r'; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'u': {
                    unsigned code = std::stoul(std::string(s_.substr(i_, 4)), nullptr, 16);
                    i_ += 4;
                    if (code >= 0xD800 && code < 0xDC00 && s_.substr(i_, 2) == "\\u") {
                        unsigned low =
                            std::stoul(std::string(s_.substr(i_ + 2, 4)), nullptr, 16);
                        i_ += 6;
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                    }
                    appendUtf8(out, code);
                    break;
                }
                default: out += e;
            }
        }
        ++i_;
        return out;
    }

    static void appendUtf8(std::string& out, unsigned c) {
        if (c < 0x80) {
            out += static_cast<char>(c);
        } else if (c < 0x800) {
            out += static_cast<char>(0xC0 | (c >> 6));
            out += static_cast<char>(0x80 | (c & 0x3F));
        } else if (c < 0x10000) {
            out += static_cast<char>(0xE0 | (c >> 12));
            out += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (c & 0x3F));
        } else {
            out += static_cast<char>(0xF0 | (c >> 18));
            out += static_cast<char>(0x80 | ((c >> 12) & 0x3F));
            out += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (c & 0x3F));
        }
    }
};

inline Value parse(std::string_view text) {
    return Parser(text).parse();
}

}  // namespace aif::json
