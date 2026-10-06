#include <vkf/vkf.hpp>

#include <algorithm>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <vector>

#include "gl_renderer.hpp"
#include "mesh.hpp"
#include "scene.hpp"
#include "vk_renderer.hpp"

namespace {

struct Measured {
    std::vector<double> issue, submit, total;

    void add(const glport::FrameTiming& t) {
        issue.push_back(t.issueMs);
        submit.push_back(t.submitMs);
        total.push_back(t.totalMs);
    }
};

// snippet:begin run-frames
template <class Renderer>
Measured runFrames(Renderer& renderer, uint32_t objects, uint32_t warmup, uint32_t frames,
                   const u4::Mat4& projection) {
    Measured measured;
    for (uint32_t frame = 0; frame < warmup + frames; ++frame) {
        const std::vector<glport::DrawData> draws =
            glport::buildDraws(objects, frame, projection);
        const glport::FrameTiming timing = renderer.renderFrame(draws);
        if (frame >= warmup) measured.add(timing);
    }
    return measured;
}
// snippet:end run-frames

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto objects = static_cast<uint32_t>(args.integer("--objects", 10'000));
        const auto frames = static_cast<uint32_t>(args.integer("--frames", 30));
        const auto warmup = static_cast<uint32_t>(args.integer("--warmup", 5));
        const auto size = static_cast<uint32_t>(args.integer("--size", 512));
        const std::string glOut = args.text("--gl-out", "glport-gl.png");
        const std::string vkOut = args.text("--vk-out", "glport-vk.png");

        vkf::Context ctx({.appName = "u4_glport"});
        const u4::Mesh cube = u4::cubeMesh();
        glport::GlRenderer gl(size, size, cube);
        glport::VkRenderer vk(ctx, size, size, cube);
        vkf::print("OpenGL: {}\n", gl.version());

        // snippet:begin port-projection
        const u4::Mat4 glProjection =
            glport::perspectiveOpenGl(u4::Pi / 4, 1.0f, 0.5f, 100.0f);
        const u4::Mat4 vkProjection = glport::vulkanFromOpenGlClip() * glProjection;
        const Measured glTimes = runFrames(gl, objects, warmup, frames, glProjection);
        const Measured vkTimes = runFrames(vk, objects, warmup, frames, vkProjection);
        // snippet:end port-projection

        vkf::print("{} draws per frame, {}x{}, median of {} frames after {} warm-up frames\n",
                   objects, size, size, frames, warmup);
        vkf::print("                            OpenGL 4.1      Vulkan\n");
        auto row = [](const char* label, const std::vector<double>& a,
                      const std::vector<double>& b) {
            vkf::print("  {:<24}{:9.2f} ms {:9.2f} ms\n", label, vkf::summarize(a).median,
                       vkf::summarize(b).median);
        };
        row("CPU, draw calls", glTimes.issue, vkTimes.issue);
        row("CPU, submit", glTimes.submit, vkTimes.submit);
        row("frame, to completion", glTimes.total, vkTimes.total);
        const char* validation = std::getenv("VKF_VALIDATION");
        if (validation == nullptr || std::string(validation) != "0") {
            vkf::print(
                "  (the Vulkan times include the validation layers: measure with "
                "VKF_VALIDATION=0)\n");
        }

        // snippet:begin compare
        const std::vector<uint8_t> glPixels = gl.readPixels();
        const std::vector<uint8_t> vkPixels = vk.readPixels();
        size_t differing = 0, covered = 0;
        for (size_t i = 0; i < glPixels.size(); i += 4) {
            int worst = 0;
            for (size_t c = 0; c < 3; ++c) {
                worst = std::max(worst, std::abs(int(glPixels[i + c]) - int(vkPixels[i + c])));
            }
            differing += worst > 2 ? 1 : 0;
            covered += vkPixels[i] != 26 || vkPixels[i + 1] != 26 || vkPixels[i + 2] != 38;
        }
        const size_t pixels = glPixels.size() / 4;
        const double share = 100.0 * double(differing) / double(pixels);
        vkf::print(
            "images: {} of {} pixels ({:.2f}%) differ by more than 2 levels; cubes "
            "cover {:.0f}%\n",
            differing, pixels, share, 100.0 * double(covered) / double(pixels));
        // snippet:end compare
        vkf::writePng(glOut, size, size, glPixels);
        vkf::writePng(vkOut, size, size, vkPixels);
        vkf::print("wrote {} and {}\n", glOut, vkOut);

        const bool passed = share < 0.5 && covered > pixels / 4;
        vkf::print("{} the OpenGL and Vulkan images agree\n", passed ? "PASS" : "FAIL");
        if (!passed) throw std::runtime_error("the OpenGL and Vulkan images differ");
    });
}
