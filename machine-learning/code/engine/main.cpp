#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

#include "engine.hpp"
#include "model.hpp"
#include "tokenizer.hpp"

namespace {

struct Options {
    std::string model, prompt = "Once upon a time";
    int tokens = 200, threads = static_cast<int>(std::thread::hardware_concurrency());
    aif::Sampling sampling;
    bool check = false, bench = false;
};

Options parse(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto value = [&]() -> std::string {
            if (i + 1 >= argc) throw std::runtime_error(a + " needs a value");
            return argv[++i];
        };
        if (a == "--prompt")
            o.prompt = value();
        else if (a == "--tokens")
            o.tokens = std::stoi(value());
        else if (a == "--threads")
            o.threads = std::stoi(value());
        else if (a == "--temperature")
            o.sampling.temperature = std::stof(value());
        else if (a == "--top-p")
            o.sampling.top_p = std::stof(value());
        else if (a == "--seed")
            o.sampling.seed = static_cast<unsigned>(std::stoul(value()));
        else if (a == "--check")
            o.check = true;
        else if (a == "--bench")
            o.bench = true;
        else if (a.rfind("--", 0) == 0)
            throw std::runtime_error("unknown option " + a);
        else
            o.model = a;
    }
    if (o.model.empty())
        throw std::runtime_error(
            "usage: aif_engine MODEL.bin [--prompt TEXT] [--tokens N] "
            "[--threads N] [--temperature T] [--top-p P] [--check] [--bench]");
    return o;
}

using Clock = std::chrono::steady_clock;
double seconds(Clock::time_point a, Clock::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

// snippet:begin check
int check(const aif::Model& model, aif::Tokenizer& tok, aif::Engine& engine) {
    const auto& ref = model.header["check"];
    std::vector<int> want;
    for (const auto& v : ref["ids"].array()) want.push_back(static_cast<int>(v.num()));
    std::vector<int> got = tok.encode(ref["prompt"].str());
    if (got != want) {
        std::printf("CHECK FAILED  the prompt's tokens differ from Python's\n");
        return 1;
    }
    const float* logits = nullptr;
    for (size_t i = 0; i < got.size(); ++i)
        logits = engine.forward(got[i], static_cast<int>(i));
    double worst = 0.0;
    const auto& expected = ref["logits"].array();
    for (size_t i = 0; i < expected.size(); ++i)
        worst = std::max(worst, std::fabs(logits[i] - expected[i].num()));
    std::printf(
        "prompt of %zu tokens: tokens identical to Python's; largest logit difference from "
        "PyTorch %.2e\n",
        got.size(), worst);
    return worst < 1e-3 ? 0 : 1;
}
// snippet:end check

}  // namespace

int main(int argc, char** argv) {
    try {
        Options o = parse(argc, argv);
        aif::Model model(o.model);
        aif::Tokenizer tok(model.header["tokenizer"]);
        aif::Engine engine(model, o.threads);
        const auto& c = model.config;
        std::printf(
            "%s: %d layers, d_model %d, vocabulary %d, %.1f MiB of weights, %d threads\n",
            o.model.c_str(), c.layers, c.d_model, c.vocab, model.bytes / 1048576.0, o.threads);
        if (o.check) return check(model, tok, engine);
        int stop = -1;
        for (const char* name : {"<|endoftext|>", "<|im_end|>"}) {
            try {
                if (stop < 0 || std::string(name) == "<|im_end|>") stop = tok.special(name);
            } catch (const std::out_of_range&) {}
        }
        std::vector<int> prompt = tok.encode(o.prompt);
        if (o.bench) {
            auto t0 = Clock::now();
            int pos = 0;
            for (int t : prompt) engine.forward(t, pos++);
            auto t1 = Clock::now();
            int next = prompt.back();
            for (int i = 0; i < o.tokens && pos < c.max_seq; ++i) {
                const float* logits = engine.forward(next, pos++);
                next = engine.sample(logits, o.sampling);
            }
            auto t2 = Clock::now();
            int made = pos - static_cast<int>(prompt.size());
            std::printf(
                "prompt: %zu tokens in %.1f ms; generation: %d tokens in %.2f s, %.1f "
                "tokens/s, "
                "%.2f ms per token\n",
                prompt.size(), seconds(t0, t1) * 1e3, made, seconds(t1, t2),
                made / seconds(t1, t2), seconds(t1, t2) * 1e3 / made);
            return 0;
        }
        std::cout << o.prompt << std::flush;
        engine.generate(prompt, o.tokens, stop, o.sampling, [&](int t) {
            if (t != stop) std::cout << tok.piece(t) << std::flush;
        });
        std::cout << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
}
