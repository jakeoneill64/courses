#include <vkf/vkf.hpp>

#include <cmath>
#include <numeric>

namespace {

struct ScalePush {
    float factor;
    uint32_t count;
};

void check(bool ok, const char* what) {
    if (!ok) throw std::runtime_error(std::string("selftest failed: ") + what);
}

}  // namespace

int main(int argc, char** argv) {
    return vkf::run([&] {
        const vkf::Args args(argc, argv);
        const auto count = static_cast<uint32_t>(args.integer("--count", 1 << 20));
        vkf::Context ctx(
            {.appName = "vkf selftest", .asyncCompute = true, .transferQueue = true});
        vkf::print("queues: main {}.{}, compute {}.{}{}, transfer {}.{}{}\n",
                   ctx.mainQueue().family, ctx.mainQueue().index, ctx.computeQueue().family,
                   ctx.computeQueue().index, ctx.hasSeparateComputeQueue() ? "" : " (shared)",
                   ctx.transferQueue().family, ctx.transferQueue().index,
                   ctx.hasSeparateTransferQueue() ? "" : " (shared)");

        // snippet:begin scale
        std::vector<float> input(count);
        std::iota(input.begin(), input.end(), 0.0f);
        const VkDeviceSize bytes = count * sizeof(float);
        vkf::Buffer src = vkf::createBuffer(
            ctx, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            vkf::MemoryUse::DeviceLocal, "input");
        vkf::Buffer dst = vkf::createBuffer(
            ctx, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vkf::MemoryUse::DeviceLocal, "output");
        vkf::upload(ctx, src, std::span<const float>(input));

        auto setLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .add(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        const VkPushConstantRange range{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ScalePush)};
        auto layout = vkf::createPipelineLayout(ctx, {setLayout.get()}, {range});
        auto module = vkf::loadShader(ctx, vkf::shaderPath("scale.comp"));
        vkf::Specialization spec;
        spec.set(0, uint32_t{256}).set(1, 0.5f);
        auto pipeline = vkf::createComputePipeline(ctx, {.layout = layout,
                                                         .module = module,
                                                         .specialization = spec.info(),
                                                         .name = "scale"});

        vkf::DescriptorPool pool(ctx);
        VkDescriptorSet set = pool.allocate(setLayout, "scale");
        vkf::DescriptorWriter()
            .buffer(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, src)
            .buffer(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, dst)
            .update(ctx, set);

        vkf::GpuTimer timer(ctx);
        const ScalePush push{2.0f, count};
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            timer.reset(cmd);
            timer.stamp(cmd);
            ctx.beginLabel(cmd, "scale");
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0,
                                    nullptr);
            vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push),
                               &push);
            vkCmdDispatch(cmd, vkf::groupCount(count, 256), 1, 1);
            ctx.endLabel(cmd);
            timer.stamp(cmd);
        });
        const double ms = timer.elapsedMs(0, 1);
        // snippet:end scale
        const std::vector<float> output = vkf::download<float>(ctx, dst, count);
        uint32_t wrong = 0;
        for (uint32_t i = 0; i < count; ++i) {
            if (std::fabs(output[i] - (input[i] * 2.0f + 0.5f)) >
                1e-3f * std::max(1.0f, input[i]))
                ++wrong;
        }
        check(wrong == 0, "scale kernel results");
        vkf::print("scale: {} floats in {:.3f} ms ({:.1f} GB/s)\n", count, ms,
                   2.0 * double(bytes) / (ms * 1e6));

        vkf::Image image = vkf::createImage(
            ctx,
            {.format = VK_FORMAT_R8G8B8A8_UNORM,
             .width = 256,
             .height = 128,
             .usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT},
            "gradient");
        auto imageLayout =
            vkf::DescriptorSetLayoutBuilder()
                .add(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT)
                .build(ctx);
        auto imagePipelineLayout = vkf::createPipelineLayout(ctx, {imageLayout.get()});
        auto gradientModule = vkf::loadShader(ctx, vkf::shaderPath("gradient.comp"));
        auto gradient = vkf::createComputePipeline(
            ctx,
            {.layout = imagePipelineLayout, .module = gradientModule, .name = "gradient"});
        VkDescriptorSet imageSet = pool.allocate(imageLayout, "gradient");
        vkf::DescriptorWriter()
            .image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, image.view, VK_IMAGE_LAYOUT_GENERAL)
            .update(ctx, imageSet);
        vkf::submitNow(ctx, [&](VkCommandBuffer cmd) {
            vkf::imageBarrier(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                              VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE,
                              VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                              VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, gradient);
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, imagePipelineLayout,
                                    0, 1, &imageSet, 0, nullptr);
            vkCmdDispatch(cmd, vkf::groupCount(256, 16), vkf::groupCount(128, 16), 1);
        });
        const std::vector<uint8_t> pixels =
            vkf::downloadImage(ctx, image, VK_IMAGE_LAYOUT_GENERAL);
        check(pixels[0] == 0 && pixels[1] == 0 && pixels[3] == 255, "gradient corner (0, 0)");
        const size_t last = (size_t(127) * 256 + 255) * 4;
        check(pixels[last] == 255 && pixels[last + 1] == 255, "gradient corner (255, 127)");
        const std::string png = args.text("--png", "selftest.png");
        vkf::writePng(png, 256, 128, pixels);
        vkf::print("gradient: wrote {}\n", png);

        auto timeline = vkf::createTimelineSemaphore(ctx, 0);
        const VkSemaphoreSignalInfo signal{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO,
                                           .semaphore = timeline,
                                           .value = 5};
        VKF_CHECK(vkSignalSemaphore(ctx.device(), &signal));
        uint64_t value = 0;
        VKF_CHECK(vkGetSemaphoreCounterValue(ctx.device(), timeline, &value));
        check(value == 5, "timeline semaphore host signal");

        // Reading an exclusive resource on another family needs an ownership transfer
        // (Chapter 3.5); writing a fresh image from UNDEFINED does not.
        vkf::Image asyncImage = vkf::createImage(ctx,
                                                 {.format = VK_FORMAT_R8G8B8A8_UNORM,
                                                  .width = 256,
                                                  .height = 128,
                                                  .usage = VK_IMAGE_USAGE_STORAGE_BIT},
                                                 "async gradient");
        VkDescriptorSet asyncSet = pool.allocate(imageLayout, "async gradient");
        vkf::DescriptorWriter()
            .image(0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, asyncImage.view,
                   VK_IMAGE_LAYOUT_GENERAL)
            .update(ctx, asyncSet);
        auto computePool = vkf::createCommandPool(ctx, ctx.computeQueue().family);
        VkCommandBuffer cmd = vkf::allocateCommandBuffer(ctx, computePool);
        vkf::beginCommands(cmd);
        vkf::imageBarrier(cmd, asyncImage, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL,
                          VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE,
                          VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                          VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, gradient);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, imagePipelineLayout, 0, 1,
                                &asyncSet, 0, nullptr);
        vkCmdDispatch(cmd, vkf::groupCount(256, 16), vkf::groupCount(128, 16), 1);
        vkf::endCommands(cmd);
        const vkf::SemaphoreSubmit done{timeline, 6, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT};
        vkf::submit(ctx.computeQueue(), std::span(&cmd, 1), {}, std::span(&done, 1));
        const VkSemaphoreWaitInfo wait{.sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
                                       .semaphoreCount = 1,
                                       .pSemaphores = timeline.ptr(),
                                       .pValues = &done.value};
        VKF_CHECK(vkWaitSemaphores(ctx.device(), &wait, UINT64_MAX));
        vkf::print("async compute: dispatch on queue family {} signalled the timeline to 6\n",
                   ctx.computeQueue().family);
        ctx.waitIdle();
        vkf::print("selftest passed\n");
    });
}
