from pathlib import Path

from PIL import Image, ImageDraw


OUTPUT = Path(__file__).resolve().parent / "abstract_sketch.png"


def main() -> None:
    image = Image.new("RGBA", (512, 512), (255, 255, 255, 255))
    draw = ImageDraw.Draw(image)
    points = [
        (92, 342), (138, 184), (236, 112), (326, 168), (414, 120),
        (382, 276), (436, 384), (294, 356), (214, 424), (170, 302),
        (92, 342), (246, 248), (382, 276),
    ]
    draw.line(points, fill=(12, 12, 18, 255), width=13, joint="curve")
    draw.ellipse((226, 228, 266, 268), outline=(12, 12, 18, 255), width=10)
    image.save(OUTPUT)


if __name__ == "__main__":
    main()
