#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

#include "json.hpp"

namespace aif {

class Tokenizer {
public:
    explicit Tokenizer(const json::Value& spec);
    std::vector<int> encode(const std::string& text);
    std::string decode(const std::vector<int>& ids) const;
    std::string piece(int id) const { return tokens_.at(id); }
    int special(const std::string& name) const { return special_.at(name); }

private:
    std::vector<std::string> tokens_;
    std::vector<int> byteId_;
    std::unordered_map<uint64_t, std::pair<int, int>> merges_;
    std::unordered_map<std::string, int> special_;
    std::unordered_map<std::string, std::vector<int>> cache_;
    bool splitDigits_ = true;

    std::vector<int> encodeChunk(const std::string& chunk) const;
    void pretokenise(const std::string& text, std::vector<std::string>& out) const;
};

}  // namespace aif
