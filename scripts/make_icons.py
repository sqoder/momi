#!/usr/bin/env python3
"""Generate original geometric macOS AppIcon and monochrome template agent glyphs for momi."""
import math
import os
import shutil
import subprocess
import tempfile
from PIL import Image, ImageDraw

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES_DIR = os.path.join(ROOT_DIR, "resources")
AGENTS_DIR = os.path.join(RESOURCES_DIR, "agents")


def build_squircle_mask(size: int, radius: int) -> Image.Image:
    s = 4
    m = Image.new("L", (size * s, size * s), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size * s, size * s], radius=radius * s, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def generate_app_icon() -> None:
    """Create a slate-navy geometric speedometer/pulse app icon + .icns."""
    cw, ch = 824, 824
    s = 4
    w, h = cw * s, ch * s

    bg = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    px = bg.load()
    top_rgb = (18, 22, 30)
    bot_rgb = (30, 38, 52)
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top_rgb[0] + (bot_rgb[0] - top_rgb[0]) * t)
        g = int(top_rgb[1] + (bot_rgb[1] - top_rgb[1]) * t)
        b = int(top_rgb[2] + (bot_rgb[2] - top_rgb[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)

    fg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(fg)

    # Outer subtle glow ring arc representing throughput gauge
    cx, cy = w // 2, int(h * 0.52)
    ring_r = int(w * 0.31)
    ring_w = int(34 * s)
    bbox = [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r]
    draw.arc(bbox, start=145, end=395, fill=(255, 255, 255, 34), width=ring_w)
    draw.arc(bbox, start=145, end=325, fill=(72, 207, 173, 255), width=ring_w)

    # Rounded end caps on active gauge arc
    for deg, col in ((145, (72, 207, 173, 255)), (325, (72, 207, 173, 255))):
        rad = math.radians(deg)
        r_mid = ring_r - ring_w / 2
        px_c = cx + r_mid * math.cos(rad)
        py_c = cy + r_mid * math.sin(rad)
        cap_r = ring_w / 2
        draw.ellipse([px_c - cap_r, py_c - cap_r, px_c + cap_r, py_c + cap_r], fill=col)

    # Three crisp rising throughput bars in center
    bar_w = int(42 * s)
    gap = int(34 * s)
    heights = [int(h * 0.16), int(h * 0.27), int(h * 0.21)]
    colors = [(238, 242, 248, 235), (72, 207, 173, 255), (238, 242, 248, 235)]
    total_bw = 3 * bar_w + 2 * gap
    start_x = cx - total_bw // 2
    base_y = int(h * 0.63)
    for i, (bh, col) in enumerate(zip(heights, colors)):
        bx0 = start_x + i * (bar_w + gap)
        bx1 = bx0 + bar_w
        by0 = base_y - bh
        draw.rounded_rectangle([bx0, by0, bx1, base_y], radius=bar_w // 2, fill=col)

    # Inner glass border
    draw.rounded_rectangle(
        [int(6 * s), int(6 * s), w - int(6 * s), h - int(6 * s)],
        radius=180 * s,
        outline=(255, 255, 255, 36),
        width=int(4 * s),
    )

    card = Image.alpha_composite(bg, fg).resize((cw, ch), Image.LANCZOS)
    card.putalpha(build_squircle_mask(cw, 185))

    master = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    master.paste(card, (100, 100), card)
    icon_png = os.path.join(RESOURCES_DIR, "icon.png")
    master.save(icon_png)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        specs = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]
        for filename, sz in specs:
            master.resize((sz, sz), Image.LANCZOS).save(os.path.join(iconset, filename))
        subprocess.run(
            ["iconutil", "-c", "icns", iconset, "-o", os.path.join(RESOURCES_DIR, "AppIcon.icns")],
            check=True,
        )


# 5x7 pixel-grid bitmap glyphs for sharp geometric monochrome template badges
GLYPHS = {
    "A": [
        "01110",
        "10001",
        "10001",
        "11111",
        "10001",
        "10001",
        "10001",
    ],
    "C": [
        "01111",
        "10000",
        "10000",
        "10000",
        "10000",
        "10000",
        "01111",
    ],
    "D": [
        "11110",
        "10001",
        "10001",
        "10001",
        "10001",
        "10001",
        "11110",
    ],
    "G": [
        "01111",
        "10000",
        "10000",
        "10111",
        "10001",
        "10001",
        "01110",
    ],
    "L": [
        "10000",
        "10000",
        "10000",
        "10000",
        "10000",
        "10000",
        "11111",
    ],
    "P": [
        "11110",
        "10001",
        "10001",
        "11110",
        "10000",
        "10000",
        "10000",
    ],
    "Q": [
        "01110",
        "10001",
        "10001",
        "10001",
        "10101",
        "10010",
        "01101",
    ],
    "S": [
        "01111",
        "10000",
        "10000",
        "01110",
        "00001",
        "00001",
        "11110",
    ],
    "X": [
        "10001",
        "10001",
        "01010",
        "00100",
        "01010",
        "10001",
        "10001",
    ],
    "Z": [
        "11111",
        "00001",
        "00010",
        "00100",
        "01000",
        "10000",
        "11111",
    ],
    "PI": [
        "11111",
        "01010",
        "01010",
        "01010",
        "01010",
        "01010",
        "01001",
    ],
}


def draw_glyph(draw: ImageDraw.ImageDraw, key: str, x0: int, y0: int, cell: int) -> None:
    rows = GLYPHS[key]
    r = max(1, cell // 4)
    for ry, row in enumerate(rows):
        for cx, ch in enumerate(row):
            if ch == "1":
                px0 = x0 + cx * cell
                py0 = y0 + ry * cell
                draw.rounded_rectangle(
                    [px0, py0, px0 + cell - 1, py0 + cell - 1],
                    radius=r,
                    fill=(0, 0, 0, 255),
                )


def make_agent_badge(filename: str, letters: list[str], is_cli: bool = False) -> None:
    """Draw pure-black monochrome glyph on transparent alpha canvas for NSImage.isTemplate = true."""
    s = 4
    sz = 128 * s
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = int(12 * s)
    box_right = sz - margin - (int(12 * s) if is_cli else 0)
    box_bottom = sz - margin - (int(12 * s) if is_cli else 0)
    draw.rounded_rectangle(
        [margin, margin, box_right, box_bottom],
        radius=int(24 * s),
        outline=(0, 0, 0, 255),
        width=int(9 * s),
    )

    inner_w = box_right - margin
    inner_h = box_bottom - margin
    cx = margin + inner_w // 2
    cy = margin + inner_h // 2

    if len(letters) == 1:
        cell = int(9.5 * s)
        gw = 5 * cell
        gh = 7 * cell
        draw_glyph(draw, letters[0], cx - gw // 2, cy - gh // 2, cell)
    else:
        cell = int(6.2 * s)
        gw = 5 * cell
        gh = 7 * cell
        gap = int(5 * s)
        total_w = gw * 2 + gap
        gx0 = cx - total_w // 2
        gy0 = cy - gh // 2
        draw_glyph(draw, letters[0], gx0, gy0, cell)
        draw_glyph(draw, letters[1], gx0 + gw + gap, gy0, cell)

    if is_cli:
        # Solid rounded CLI indicator badge at bottom-right (carved transparent '>_')
        bx0 = sz - int(58 * s)
        by0 = sz - int(50 * s)
        bx1 = sz - int(6 * s)
        by1 = sz - int(6 * s)
        draw.rounded_rectangle([bx0, by0, bx1, by1], radius=int(10 * s), fill=(0, 0, 0, 255))
        # Cut '>' and '_' inside badge with transparent pixels
        cut = int(4.5 * s)
        draw.line(
            [
                (bx0 + int(11 * s), by0 + int(13 * s)),
                (bx0 + int(22 * s), by0 + int(22 * s)),
                (bx0 + int(11 * s), by0 + int(31 * s)),
            ],
            fill=(0, 0, 0, 0),
            width=cut,
            joint="curve",
        )
        draw.line(
            [
                (bx0 + int(27 * s), by0 + int(31 * s)),
                (bx0 + int(41 * s), by0 + int(31 * s)),
            ],
            fill=(0, 0, 0, 0),
            width=cut,
        )

    out = img.resize((128, 128), Image.LANCZOS)
    # Enforce strict template invariant: RGB = (0, 0, 0) on every pixel, alpha carries shape
    px = out.load()
    for y in range(128):
        for x in range(128):
            _, _, _, a = px[x, y]
            px[x, y] = (0, 0, 0, a)
    out.save(os.path.join(AGENTS_DIR, filename))


def main() -> None:
    os.makedirs(AGENTS_DIR, exist_ok=True)
    generate_app_icon()
    specs = [
        ("agent_alma.png", ["A", "L"], False),
        ("agent_antigravity.png", ["A", "G"], False),
        ("agent_antigravity_cli.png", ["A", "G"], True),
        ("agent_claude.png", ["C", "C"], False),
        ("agent_codex.png", ["C", "X"], False),
        ("agent_codex_cli.png", ["C", "X"], True),
        ("agent_deepseek.png", ["D", "S"], False),
        ("agent_pi.png", ["PI"], False),
        ("agent_qoder.png", ["Q"], False),
        ("agent_zcode.png", ["Z"], False),
    ]
    for fname, letters, is_cli in specs:
        make_agent_badge(fname, letters, is_cli=is_cli)
    print(f"Generated AppIcon.icns, icon.png, and {len(specs)} monochrome template badges.")


if __name__ == "__main__":
    main()
