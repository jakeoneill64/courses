#pragma once

#if defined(__APPLE__)
#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl3.h>
#else
// Khronos' glcorearb.h: its prototypes only supply types, so nothing links against OpenGL.
#define GL_GLEXT_PROTOTYPES
#include <GL/glcorearb.h>
#endif

// clang-format off
// snippet:begin function-table
#define GLPORT_FUNCTIONS(X)                                                                   \
    X(GenVertexArrays) X(BindVertexArray) X(DeleteVertexArrays) X(GenBuffers) X(BindBuffer)   \
    X(BufferData) X(DeleteBuffers) X(VertexAttribPointer) X(EnableVertexAttribArray)         \
    X(CreateShader) X(ShaderSource) X(CompileShader) X(GetShaderiv) X(GetShaderInfoLog)      \
    X(DeleteShader) X(CreateProgram) X(AttachShader) X(LinkProgram) X(GetProgramiv)          \
    X(GetProgramInfoLog) X(DeleteProgram) X(UseProgram) X(GetUniformLocation)                \
    X(UniformMatrix4fv) X(Uniform4fv) X(GenFramebuffers) X(BindFramebuffer)                  \
    X(FramebufferRenderbuffer) X(CheckFramebufferStatus) X(DeleteFramebuffers)               \
    X(GenRenderbuffers) X(BindRenderbuffer) X(RenderbufferStorage) X(DeleteRenderbuffers)    \
    X(Viewport) X(ClearColor) X(ClearDepth) X(Clear) X(Enable) X(DepthFunc) X(DrawElements)  \
    X(ReadPixels) X(PixelStorei) X(FenceSync) X(ClientWaitSync) X(DeleteSync) X(Flush)       \
    X(GetError) X(GetString)

struct GlApi {
#define GLPORT_DECLARE(name) decltype(&::gl##name) name = nullptr;
    GLPORT_FUNCTIONS(GLPORT_DECLARE)
#undef GLPORT_DECLARE
};

GlApi loadGl();
// snippet:end function-table
// clang-format on
