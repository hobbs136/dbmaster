#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate Gumroad marketing assets from real app screenshots.
Uses PIL and the manual screenshots in assets/gumroad/screens/.
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).parent
SCREENS_DIR = ROOT / "screens"
OUT_DIR = ROOT
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Brand colors
BG = "#0B0B0E"
BG_CARD = "#15151A"
ACCENT = "#0A84FF"
TEXT_PRIMARY = "#FFFFFF"
TEXT_SECONDARY = "#A1A1AA"
TEXT_MUTED = "#71717A"
BORDER = "#27272A"


def get_font(size, bold=False):
    candidates = []
    if bold:
        candidates = [
            "C:/Windows/Fonts/SegoeUIbd.ttf",
            "C:/Windows/Fonts/arialbd.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ]
    else:
        candidates = [
            "C:/Windows/Fonts/SegoeUI.ttf",
            "C:/Windows/Fonts/arial.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))


def make_gradient(width, height, top_hex="#0B0B0E", bottom_hex="#0F172A"):
    img = Image.new("RGB", (width, height), hex_to_rgb(top_hex))
    draw = ImageDraw.Draw(img)
    top = hex_to_rgb(top_hex)
    bottom = hex_to_rgb(bottom_hex)
    for y in range(height):
        ratio = y / height
        r = int(top[0] * (1 - ratio) + bottom[0] * ratio)
        g = int(top[1] * (1 - ratio) + bottom[1] * ratio)
        b = int(top[2] * (1 - ratio) + bottom[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))
    return img


def load_screen(name, target_width=None, target_height=None, crop_box=None, crop_bottom=0):
    """Load a screenshot, optionally crop, resize, add rounded corners."""
    img = Image.open(SCREENS_DIR / name).convert("RGB")
    w, h = img.size

    if crop_box:
        x1, y1, x2, y2 = crop_box
        x1 = max(0, x1)
        y1 = max(0, y1)
        x2 = min(w, x2)
        y2 = min(h, y2)
        img = img.crop((x1, y1, x2, y2))
    elif crop_bottom > 0:
        img = img.crop((0, 0, w, h - crop_bottom))

    if target_width and target_height:
        img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
    elif target_width:
        ratio = target_width / img.width
        target_height = int(img.height * ratio)
        img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
    elif target_height:
        ratio = target_height / img.height
        target_width = int(img.width * ratio)
        img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)

    return img


def round_corners(img, radius=16):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, w, h), radius=radius, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def add_shadow(img, radius=20, opacity=60):
    w, h = img.size
    shadow = Image.new("RGBA", (w + radius * 2, h + radius * 2), (0, 0, 0, 0))
    shadow.paste(img, (radius, radius), img)
    alpha = shadow.split()[3]
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius))
    shadow = Image.merge("RGBA", (Image.new("L", shadow.size, 0), Image.new("L", shadow.size, 0), Image.new("L", shadow.size, 0), alpha))
    r, g, b, a = shadow.split()
    a = a.point(lambda x: int(x * opacity / 255))
    shadow = Image.merge("RGBA", (r, g, b, a))
    return shadow


def compose_rounded_with_shadow(img, canvas, x, y, radius=16, shadow_radius=20, shadow_opacity=60):
    rounded = round_corners(img, radius)
    shadow = add_shadow(rounded, shadow_radius, shadow_opacity)
    canvas = canvas.convert("RGBA")
    canvas.paste(shadow, (x - shadow_radius, y - shadow_radius), shadow)
    canvas.paste(rounded, (x, y), rounded)
    return canvas


def create_cover_with_screenshots():
    """Cover image using real 8_db_type screenshot, cropped to dialog."""
    width, height = 1280, 720
    canvas = make_gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    margin_left = 60
    top_y = 120

    # Logo
    draw.rounded_rectangle((margin_left, top_y, margin_left + 44, top_y + 44), radius=10, fill=hex_to_rgb(ACCENT))
    font_icon = get_font(24, bold=True)
    draw.text((margin_left + 13, top_y + 8), "D", font=font_icon, fill=hex_to_rgb(TEXT_PRIMARY))

    font_title = get_font(52, bold=True)
    draw.text((margin_left, top_y + 70), "DbMaster", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))

    font_sub = get_font(24)
    draw.text((margin_left, top_y + 145), "AI-Powered Database Manager", font=font_sub, fill=hex_to_rgb(TEXT_PRIMARY))

    font_body = get_font(18)
    lines = [
        "8 database engines · Connection groups",
        "Data Sync · Schema Diff & Sync · AI Analysis",
    ]
    y = top_y + 205
    for line in lines:
        draw.text((margin_left, y), line, font=font_body, fill=hex_to_rgb(TEXT_SECONDARY))
        y += 32

    # Pricing pills
    pill_y = top_y + 290
    draw.rounded_rectangle((margin_left, pill_y, margin_left + 180, pill_y + 42), radius=21, fill=hex_to_rgb(ACCENT))
    font_pill = get_font(18, bold=True)
    draw.text((margin_left + 20, pill_y + 9), "$99 / year", font=font_pill, fill=hex_to_rgb(TEXT_PRIMARY))
    draw.rounded_rectangle((margin_left + 200, pill_y, margin_left + 390, pill_y + 42), radius=21, outline=hex_to_rgb(BORDER), width=2)
    draw.text((margin_left + 220, pill_y + 9), "$199 lifetime", font=font_pill, fill=hex_to_rgb(TEXT_PRIMARY))

    # Screenshot on right - crop to the New Connection dialog
    ss = load_screen("8_db_type.png", target_height=540, crop_box=(1300, 280, 3000, 1900))
    ss_x = width - ss.width - 60
    ss_y = (height - ss.height) // 2 + 10
    canvas = compose_rounded_with_shadow(ss, canvas, ss_x, ss_y, radius=20)

    draw = ImageDraw.Draw(canvas)
    font_foot = get_font(16)
    draw.text((margin_left, height - 70), "Desktop app for macOS, Windows & Linux", font=font_foot, fill=hex_to_rgb(TEXT_MUTED))

    out_path = OUT_DIR / "cover-1280x720.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_db_types_showcase():
    """Showcase image for 8 database types."""
    width, height = 1200, 800
    canvas = make_gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    font_title = get_font(42, bold=True)
    draw.text((width // 2 - 260, 60), "Connect to 8 Database Engines", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(20)
    draw.text((width // 2 - 220, 120), "MySQL · PostgreSQL · SQLite · MongoDB · Redis · Doris · TDengine · SQL Server", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    ss = load_screen("8_db_type.png", target_height=560, crop_box=(1300, 280, 3000, 1900))
    ss_w, ss_h = ss.size
    x = (width - ss_w) // 2
    y = 190
    canvas = compose_rounded_with_shadow(ss, canvas, x, y, radius=20)

    out_path = OUT_DIR / "db-types-1200x800.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_connection_management_showcase():
    """Showcase connection grouping and import/export."""
    width, height = 1200, 800
    canvas = make_gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    font_title = get_font(40, bold=True)
    draw.text((width // 2 - 280, 50), "Organize & Migrate Connections", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(20)
    draw.text((width // 2 - 240, 105), "Create groups, drag connections, export/import with password protection", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    # Left: create group - crop to dialog
    ss1 = load_screen("create_connection_group.png", target_height=500, crop_box=(1200, 500, 2600, 1700))
    ss1_w = 440
    ss1 = ss1.resize((ss1_w, int(ss1.height * ss1_w / ss1.width)), Image.Resampling.LANCZOS)

    # Right: export connections - crop to dialog
    ss2 = load_screen("export_db_connections.png", target_height=500, crop_box=(1200, 500, 2600, 1700))
    ss2_w = 440
    ss2 = ss2.resize((ss2_w, int(ss2.height * ss2_w / ss2.width)), Image.Resampling.LANCZOS)

    gap = 80
    total_w = ss1.width + ss2.width + gap
    start_x = (width - total_w) // 2
    y = 170

    canvas = compose_rounded_with_shadow(ss1, canvas, start_x, y, radius=16)
    canvas = compose_rounded_with_shadow(ss2, canvas, start_x + ss1.width + gap, y, radius=16)

    draw = ImageDraw.Draw(canvas)
    font_label = get_font(18, bold=True)
    draw.text((start_x + 20, y + ss1.height + 20), "Create Groups", font=font_label, fill=hex_to_rgb(TEXT_PRIMARY))
    draw.text((start_x + ss1.width + gap + 20, y + ss2.height + 20), "Export / Import", font=font_label, fill=hex_to_rgb(TEXT_PRIMARY))

    out_path = OUT_DIR / "connection-management-1200x800.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_data_sync_showcase():
    """Showcase Data Sync with custom key / slice."""
    width, height = 1200, 800
    canvas = make_gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    font_title = get_font(40, bold=True)
    draw.text((width // 2 - 240, 50), "Cross-Database Data Sync", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(20)
    draw.text((width // 2 - 290, 105), "Sync rows across connections. Custom segment key, page size, and target strategy.", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    # Main: data_sync.png - crop to Data Sync dialog
    ss1 = load_screen("data_sync.png", target_height=500, crop_box=(1100, 250, 3000, 1800), crop_bottom=70)
    ss1_w = 620
    ss1 = ss1.resize((ss1_w, int(ss1.height * ss1_w / ss1.width)), Image.Resampling.LANCZOS)

    # Inset: data_sync_slice.png - crop to Segment/Strategy area
    ss2 = load_screen("data_sync_slice.png", target_height=300, crop_box=(1100, 450, 2600, 1650), crop_bottom=70)
    ss2_w = 380
    ss2 = ss2.resize((ss2_w, int(ss2.height * ss2_w / ss2.width)), Image.Resampling.LANCZOS)

    start_x = 70
    y = 170
    canvas = compose_rounded_with_shadow(ss1, canvas, start_x, y, radius=16)
    canvas = compose_rounded_with_shadow(ss2, canvas, start_x + ss1.width + 40, y + 120, radius=16)

    out_path = OUT_DIR / "data-sync-1200x800.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_schema_diff_showcase():
    """Showcase Schema Diff & Sync."""
    width, height = 1200, 800
    canvas = make_gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    font_title = get_font(40, bold=True)
    draw.text((width // 2 - 220, 50), "Schema Diff & Sync", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(20)
    draw.text((width // 2 - 270, 105), "Compare schemas across databases and generate migration DDL with one click.", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    ss = load_screen("scheme_diff_sync.png", target_height=540, crop_box=(200, 100, 3700, 1900))
    ss_w, ss_h = ss.size
    x = (width - ss_w) // 2
    y = 170
    canvas = compose_rounded_with_shadow(ss, canvas, x, y, radius=20)

    out_path = OUT_DIR / "schema-diff-1200x800.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_ai_analysis_showcase():
    """Showcase AI analysis of execution results/errors."""
    width, height = 1200, 800
    canvas = make_gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    font_title = get_font(40, bold=True)
    draw.text((width // 2 - 260, 50), "One-Click AI Analysis", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(20)
    draw.text((width // 2 - 250, 105), "Let AI diagnose errors, explain queries, and suggest fixes instantly.", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    ss = load_screen("direct_to_ai_ana.png", target_height=540, crop_bottom=50)
    ss_w, ss_h = ss.size
    x = (width - ss_w) // 2
    y = 170
    canvas = compose_rounded_with_shadow(ss, canvas, x, y, radius=20)

    out_path = OUT_DIR / "ai-analysis-1200x800.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_feature_gallery():
    """A composite gallery image for social sharing / description."""
    width, height = 1200, 1200
    canvas = make_gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    font_title = get_font(42, bold=True)
    draw.text((width // 2 - 260, 50), "DbMaster in Action", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(20)
    draw.text((width // 2 - 180, 105), "Real screens. Real features.", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    shots = [
        ("8_db_type.png", "8 Database Engines", (1300, 280, 3000, 1900)),
        ("scheme_diff_sync.png", "Schema Diff & Sync", (200, 100, 3700, 1900)),
        ("data_sync.png", "Cross-Database Data Sync", (1100, 250, 3000, 1800)),
        ("direct_to_ai_ana.png", "AI Error Analysis", None),
    ]

    thumb_w, thumb_h = 500, 360
    gap_x, gap_y = 60, 80
    start_x = (width - (thumb_w * 2 + gap_x)) // 2
    start_y = 170

    font_label = get_font(18, bold=True)

    for i, (name, label, crop) in enumerate(shots):
        col = i % 2
        row = i // 2
        x = start_x + col * (thumb_w + gap_x)
        y = start_y + row * (thumb_h + gap_y)

        crop_bottom = 70 if name == "data_sync.png" else (50 if name == "direct_to_ai_ana.png" else 0)
        if crop:
            ss = load_screen(name, target_width=thumb_w, crop_box=crop, crop_bottom=crop_bottom)
        else:
            ss = load_screen(name, target_width=thumb_w, crop_bottom=crop_bottom)

        if ss.height > thumb_h:
            ss = ss.crop((0, 0, thumb_w, thumb_h))
        else:
            ss = ss.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)

        canvas = compose_rounded_with_shadow(ss, canvas, x, y, radius=16)
        draw = ImageDraw.Draw(canvas)
        draw.text((x, y + thumb_h + 15), label, font=font_label, fill=hex_to_rgb(TEXT_PRIMARY))

    out_path = OUT_DIR / "feature-gallery-1200x1200.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


if __name__ == "__main__":
    print("Generating screenshot-based Gumroad assets...")
    create_cover_with_screenshots()
    create_db_types_showcase()
    create_connection_management_showcase()
    create_data_sync_showcase()
    create_schema_diff_showcase()
    create_ai_analysis_showcase()
    create_feature_gallery()
    print("Done.")
