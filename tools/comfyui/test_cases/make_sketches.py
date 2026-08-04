from pathlib import Path

from PIL import Image, ImageDraw


OUTPUT = Path(__file__).resolve().parent / "sketches"


def save(name: str, strokes: list[list[tuple[int, int]]]) -> None:
    image = Image.new("RGB", (512, 512), "white")
    draw = ImageDraw.Draw(image)
    for stroke in strokes:
        draw.line(stroke, fill="black", width=14, joint="curve")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT / name, format="PNG")


save(
    "case_a.png",
    [
        [(75, 220), (320, 195), (435, 205)],
        [(75, 270), (320, 285), (435, 275)],
        [(105, 220), (100, 350), (145, 350), (175, 272)],
        [(310, 210), (450, 225)],
        [(310, 240), (455, 245)],
        [(310, 270), (445, 268)],
    ],
)
save(
    "case_c.png",
    [
        [(65, 275), (165, 260), (430, 180)],
        [(65, 315), (165, 305), (430, 225)],
        [(155, 260), (155, 305)],
        [(230, 245), (250, 215), (270, 248), (290, 205), (310, 230), (330, 190), (350, 215), (375, 180)],
        [(70, 255), (45, 230)],
        [(95, 320), (70, 355)],
    ],
)
save(
    "case_d.png",
    [
        [(145, 110), (145, 330)],
        [(330, 110), (330, 330)],
        [(145, 110), (330, 110)],
        [(145, 220), (330, 220)],
        [(145, 330), (330, 330)],
        [(180, 330), (155, 450)],
        [(295, 330), (325, 450)],
        [(330, 220), (440, 245)],
    ],
)
