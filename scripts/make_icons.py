#!/usr/bin/env python3
"""Generate original geometric macOS AppIcon and icon.png for momi."""
import math
import os
import subprocess
import tempfile
from PIL import Image, ImageDraw

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES_DIR = os.path.join(ROOT_DIR, "resources")


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


def main() -> None:
    os.makedirs(RESOURCES_DIR, exist_ok=True)
    generate_app_icon()
    print("Generated AppIcon.icns and icon.png.")


if __name__ == "__main__":
    main()
