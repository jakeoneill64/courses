import os

# Free the GPU allocator's cache early: batches of varying shape otherwise grow it into swap.
os.environ.setdefault("PYTORCH_MPS_LOW_WATERMARK_RATIO", "0.5")
