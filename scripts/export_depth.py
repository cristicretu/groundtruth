#!/usr/bin/env python3
"""Export Depth Anything V2 Small to CoreML (.mlpackage)."""

import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct
from transformers import AutoModelForDepthEstimation
from contextlib import contextmanager

MODEL_ID = "depth-anything/Depth-Anything-V2-Small-hf"
INPUT_SIZE = (518, 518)
OUTPUT_NAME = "DepthAnythingV2Small"


class DepthWrapper(nn.Module):
    """Wraps the HF model to return just the depth tensor."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, pixel_values):
        return self.model(pixel_values).predicted_depth


@contextmanager
def force_bicubic_to_bilinear():
    """
    CoreML PyTorch frontend does not support upsample_bicubic2d.
    Patch torch interpolate at trace-time so bicubic ops become bilinear.
    """
    original_interpolate = F.interpolate

    def patched_interpolate(
        input,
        size=None,
        scale_factor=None,
        mode="nearest",
        align_corners=None,
        recompute_scale_factor=None,
        antialias=False,
    ):
        if mode == "bicubic":
            mode = "bilinear"
        return original_interpolate(
            input,
            size=size,
            scale_factor=scale_factor,
            mode=mode,
            align_corners=align_corners,
            recompute_scale_factor=recompute_scale_factor,
            antialias=antialias,
        )

    F.interpolate = patched_interpolate
    try:
        yield
    finally:
        F.interpolate = original_interpolate


def convert_traced_model(traced):
    print("Converting to CoreML...")
    return ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, *INPUT_SIZE),
                scale=1.0 / (255.0 * 0.226),
                bias=[
                    -0.485 / 0.229,
                    -0.456 / 0.224,
                    -0.406 / 0.225,
                ],
            )
        ],
        minimum_deployment_target=ct.target.iOS16,
    )


def main():
    print(f"Loading {MODEL_ID}...")
    model = AutoModelForDepthEstimation.from_pretrained(MODEL_ID)
    wrapper = DepthWrapper(model)
    wrapper.eval()

    dummy = torch.randn(1, 3, *INPUT_SIZE)
    print("Tracing model...")
    traced = torch.jit.trace(wrapper, dummy)

    try:
        mlmodel = convert_traced_model(traced)
    except NotImplementedError as error:
        if "upsample_bicubic2d" not in str(error):
            raise
        print("CoreML does not support upsample_bicubic2d; retrying with bilinear fallback...")
        with force_bicubic_to_bilinear():
            traced = torch.jit.trace(wrapper, dummy)
        mlmodel = convert_traced_model(traced)

    output_path = f"{OUTPUT_NAME}.mlpackage"
    mlmodel.save(output_path)
    print(f"Saved to {output_path}")
    print()
    print("To compile for on-device use:")
    print(f"  xcrun coremlcompiler compile {output_path} .")
    print()
    print(f"This produces {OUTPUT_NAME}.mlmodelc/")


if __name__ == "__main__":
    main()
