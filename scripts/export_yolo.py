#!/usr/bin/env python3
"""
Export YOLO11n to CoreML with NMS baked in.

Usage:
    pip install ultralytics
    python scripts/export_yolo.py          # FP16 (default, best for Neural Engine)
    python scripts/export_yolo.py --fp32   # FP32 (for debugging)

Output:
    yolo11n.mlpackage — drag into Xcode, it compiles to yolo11n.mlmodelc

COCO classes we use (everything else is filtered in Swift):
    0=person, 1=bicycle, 2=car, 3=motorcycle, 5=bus, 7=truck,
    9=traffic light, 11=stop sign, 16=dog
"""

import argparse
from ultralytics import YOLO


def main():
    parser = argparse.ArgumentParser(description="Export YOLO11n to CoreML")
    parser.add_argument(
        "--fp32", action="store_true",
        help="Export in FP32 instead of FP16 (default is FP16 for Neural Engine)"
    )
    args = parser.parse_args()

    model = YOLO("yolo11n.pt")

    half = not args.fp32

    model.export(
        format="coreml",
        nms=True,
        half=half,
        imgsz=640,
    )

    precision = "FP32" if args.fp32 else "FP16"
    print(f"\nExported yolo11n.mlpackage ({precision})")
    print("Drag into Xcode project to use.")


if __name__ == "__main__":
    main()
