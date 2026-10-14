#include "gl_renderer.hpp"

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <vkf/timing.hpp>

#include <cstddef>
#include <stdexcept>

namespace glport {
namespace {

// snippet:begin shaders
const char* const VertexSource = R"(#version 410 core
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
uniform mat4 mvp;
uniform vec4 tint;
out vec3 faceColor;
void main() {
    gl_Position = mvp * vec4(inPosition, 1.0);
    faceColor = (inNormal * 0.5 + 0.5) * tint.rgb;
}
)";

const char* const FragmentSource = R"(#version 410 core
in vec3 faceColor;
layout(location = 0) out vec4 outColor;
void main() {
    outColor = vec4(faceColor, 1.0);
}
)";
// snippet:end shaders

}  // namespace

template <class Function>
void loadFunction(Function& slot, const char* name) {
    slot = reinterpret_cast<Function>(glfwGetProcAddress(name));
    if (slot == nullptr) throw std::runtime_error(std::string("OpenGL lacks ") + name);
}

GlApi loadGl() {
    GlApi gl;
#define GLPORT_LOAD(name) loadFunction(gl.name, "gl" #name);
    GLPORT_FUNCTIONS(GLPORT_LOAD)
#undef GLPORT_LOAD
    return gl;
}

// snippet:begin context
GlRenderer::GlRenderer(uint32_t width, uint32_t height, const u4::Mesh& mesh)
    : width_(width), height_(height) {
    if (!glfwInit()) throw std::runtime_error("glfwInit failed");
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    window_ = glfwCreateWindow(64, 64, "u4_glport", nullptr, nullptr);
    if (window_ == nullptr) {
        glfwTerminate();
        throw std::runtime_error("cannot create an OpenGL 4.1 core context");
    }
    glfwMakeContextCurrent(window_);
    glfwSwapInterval(0);
    gl_ = loadGl();
    // snippet:end context

    // snippet:begin buffers
    gl_.GenVertexArrays(1, &vertexArray_);
    gl_.BindVertexArray(vertexArray_);
    gl_.GenBuffers(1, &vertexBuffer_);
    gl_.BindBuffer(GL_ARRAY_BUFFER, vertexBuffer_);
    gl_.BufferData(GL_ARRAY_BUFFER, GLsizeiptr(mesh.vertices.size() * sizeof(u4::MeshVertex)),
                   mesh.vertices.data(), GL_STATIC_DRAW);
    gl_.GenBuffers(1, &indexBuffer_);
    gl_.BindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer_);
    gl_.BufferData(GL_ELEMENT_ARRAY_BUFFER, GLsizeiptr(mesh.indices.size() * sizeof(uint16_t)),
                   mesh.indices.data(), GL_STATIC_DRAW);
    gl_.VertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(u4::MeshVertex),
                            reinterpret_cast<const void*>(offsetof(u4::MeshVertex, position)));
    gl_.VertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(u4::MeshVertex),
                            reinterpret_cast<const void*>(offsetof(u4::MeshVertex, normal)));
    gl_.EnableVertexAttribArray(0);
    gl_.EnableVertexAttribArray(1);
    indexCount_ = GLsizei(mesh.indices.size());
    // snippet:end buffers

    // snippet:begin pipeline
    auto compile = [&](GLenum stage, const char* source) {
        const GLuint shader = gl_.CreateShader(stage);
        gl_.ShaderSource(shader, 1, &source, nullptr);
        gl_.CompileShader(shader);
        GLint ok = GL_FALSE;
        gl_.GetShaderiv(shader, GL_COMPILE_STATUS, &ok);
        if (!ok) {
            char log[1024] = {};
            gl_.GetShaderInfoLog(shader, sizeof(log), nullptr, log);
            throw std::runtime_error(std::string("GLSL compile error: ") + log);
        }
        return shader;
    };
    const GLuint vertexShader = compile(GL_VERTEX_SHADER, VertexSource);
    const GLuint fragmentShader = compile(GL_FRAGMENT_SHADER, FragmentSource);
    program_ = gl_.CreateProgram();
    gl_.AttachShader(program_, vertexShader);
    gl_.AttachShader(program_, fragmentShader);
    gl_.LinkProgram(program_);
    GLint linked = GL_FALSE;
    gl_.GetProgramiv(program_, GL_LINK_STATUS, &linked);
    if (!linked) throw std::runtime_error("GLSL link error");
    gl_.DeleteShader(vertexShader);
    gl_.DeleteShader(fragmentShader);
    mvpLocation_ = gl_.GetUniformLocation(program_, "mvp");
    colorLocation_ = gl_.GetUniformLocation(program_, "tint");
    // snippet:end pipeline

    // snippet:begin targets
    gl_.GenRenderbuffers(1, &colorBuffer_);
    gl_.BindRenderbuffer(GL_RENDERBUFFER, colorBuffer_);
    gl_.RenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, GLsizei(width), GLsizei(height));
    gl_.GenRenderbuffers(1, &depthBuffer_);
    gl_.BindRenderbuffer(GL_RENDERBUFFER, depthBuffer_);
    gl_.RenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT32F, GLsizei(width),
                            GLsizei(height));
    gl_.GenFramebuffers(1, &framebuffer_);
    gl_.BindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
    gl_.FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER,
                                colorBuffer_);
    gl_.FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER,
                                depthBuffer_);
    if (gl_.CheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        throw std::runtime_error("the OpenGL framebuffer is incomplete");
    }
    gl_.Enable(GL_DEPTH_TEST);
    gl_.DepthFunc(GL_LESS);
    gl_.Enable(GL_CULL_FACE);
    // snippet:end targets
    checkErrors("set-up");
}

GlRenderer::~GlRenderer() {
    gl_.DeleteFramebuffers(1, &framebuffer_);
    gl_.DeleteRenderbuffers(1, &colorBuffer_);
    gl_.DeleteRenderbuffers(1, &depthBuffer_);
    gl_.DeleteProgram(program_);
    gl_.DeleteBuffers(1, &vertexBuffer_);
    gl_.DeleteBuffers(1, &indexBuffer_);
    gl_.DeleteVertexArrays(1, &vertexArray_);
    glfwDestroyWindow(window_);
    glfwTerminate();
}

void GlRenderer::checkErrors(const char* where) {
    const GLenum error = gl_.GetError();
    if (error != GL_NO_ERROR) {
        throw std::runtime_error(std::string("OpenGL error during ") + where + ": " +
                                 std::to_string(error));
    }
}

std::string GlRenderer::version() const {
    return reinterpret_cast<const char*>(gl_.GetString(GL_VERSION));
}

FrameTiming GlRenderer::renderFrame(std::span<const DrawData> draws) {
    FrameTiming timing;
    const vkf::CpuTimer timer;
    // snippet:begin frame
    gl_.BindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
    gl_.Viewport(0, 0, GLsizei(width_), GLsizei(height_));
    gl_.ClearColor(0.10f, 0.10f, 0.15f, 1.0f);
    gl_.ClearDepth(1.0);
    gl_.Clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    // snippet:begin per-draw
    gl_.UseProgram(program_);
    gl_.BindVertexArray(vertexArray_);
    for (const DrawData& draw : draws) {
        gl_.UniformMatrix4fv(mvpLocation_, 1, GL_FALSE, &draw.mvp.m[0][0]);
        gl_.Uniform4fv(colorLocation_, 1, draw.color);
        gl_.DrawElements(GL_TRIANGLES, indexCount_, GL_UNSIGNED_SHORT, nullptr);
    }
    // snippet:end per-draw
    // snippet:end frame
    timing.issueMs = timer.elapsedMs();

    // snippet:begin sync
    const GLsync fence = gl_.FenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    gl_.Flush();
    timing.submitMs = timer.elapsedMs() - timing.issueMs;
    const GLenum waited =
        gl_.ClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, 10'000'000'000);
    gl_.DeleteSync(fence);
    if (waited != GL_ALREADY_SIGNALED && waited != GL_CONDITION_SATISFIED) {
        throw std::runtime_error("glClientWaitSync did not see the frame finish");
    }
    // snippet:end sync
    timing.totalMs = timer.elapsedMs();
    checkErrors("a frame");
    return timing;
}

std::vector<uint8_t> GlRenderer::readPixels() {
    // snippet:begin readback
    std::vector<uint8_t> bottomUp(size_t(width_) * height_ * 4);
    gl_.BindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
    gl_.PixelStorei(GL_PACK_ALIGNMENT, 1);
    gl_.ReadPixels(0, 0, GLsizei(width_), GLsizei(height_), GL_RGBA, GL_UNSIGNED_BYTE,
                   bottomUp.data());
    // snippet:end readback
    checkErrors("glReadPixels");
    std::vector<uint8_t> topDown(bottomUp.size());
    const size_t row = size_t(width_) * 4;
    for (uint32_t y = 0; y < height_; ++y) {
        std::copy_n(&bottomUp[(height_ - 1 - y) * row], row, &topDown[y * row]);
    }
    return topDown;
}

}  // namespace glport
