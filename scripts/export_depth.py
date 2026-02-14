#!/usr/bin/env python3
"""Export Depth Anything V2 Small to CoreML (.mlpackage)."""

import torch
import torch.nn as nn
import coremltools as ct
from transformers import AutoModelForDepthEstimation

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


def main():
    print(f"Loading {MODEL_ID}...")
    model = AutoModelForDepthEstimation.from_pretrained(MODEL_ID)
    wrapper = DepthWrapper(model)
    wrapper.eval()

    print("Tracing model...")
    dummy = torch.randn(1, 3, *INPUT_SIZE)
    traced = torch.jit.trace(wrapper, dummy)

    print("Converting to CoreML...")
    mlmodel = ct.convert(
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
