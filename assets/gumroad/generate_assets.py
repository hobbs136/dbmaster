#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate Gumroad marketing assets for DbMaster using existing app screenshots.
No external AI APIs required — uses PIL and system fonts.
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

# Paths
ROOT = Path(__file__).parent
SCREENSHOT = ROOT.parents[1] / "screenshots" / "dbmaster_main_2560x1600_raw.png"
OUT_DIR = ROOT
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Brand colors (matching the app's dark theme)
BG = "#0B0B0E"
BG_CARD = "#15151A"
BG_ELEVATED = "#1E1E24"
ACCENT = "#0A84FF"
ACCENT_GLOW = "#0A84FF"
TEXT_PRIMARY = "#FFFFFF"
TEXT_SECONDARY = "#A1A1AA"
TEXT_MUTED = "#71717A"
BORDER = "#27272A"
CHECK_GREEN = "#34D399"

# Font helpers
def get_font(size, bold=False):
    """Try to load a decent system font with fallback."""
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
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_rounded_rect(draw, xy, radius, fill, outline=None, width=1):
    """Draw a rounded rectangle."""
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def add_gradient_background(img, color_top, color_bottom):
    """Add a subtle vertical gradient to an image."""
    width, height = img.size
    base = Image.new("RGB", (width, height), color_top)
    draw = ImageDraw.Draw(base)
    for y in range(height):
        ratio = y / height
        r = int(color_top[0] * (1 - ratio) + color_bottom[0] * ratio)
        g = int(color_top[1] * (1 - ratio) + color_bottom[1] * ratio)
        b = int(color_top[2] * (1 - ratio) + color_bottom[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))
    return base


def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))


def load_screenshot(width, height, crop_bottom=0):
    """Load and resize the app screenshot, adding rounded corners and shadow."""
    img = Image.open(SCREENSHOT).convert("RGB")
    if crop_bottom > 0:
        img = img.crop((0, 0, img.width, img.height - crop_bottom))
    img = img.resize((width, height), Image.Resampling.LANCZOS)
    # Add subtle rounded corners
    radius = 12
    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((0, 0, width, height), radius=radius, fill=255)
    output = Image.new("RGB", (width, height), hex_to_rgb(BG))
    output.paste(img, (0, 0), mask)
    return output


def create_cover():
    """Gumroad cover image: 1280x720."""
    width, height = 1280, 720
    img = Image.new("RGB", (width, height), hex_to_rgb(BG))
    draw = ImageDraw.Draw(img)

    # Subtle gradient
    top = hex_to_rgb("#0B0B0E")
    bottom = hex_to_rgb("#0F172A")
    for y in range(height):
        ratio = y / height
        r = int(top[0] * (1 - ratio) + bottom[0] * ratio)
        g = int(top[1] * (1 - ratio) + bottom[1] * ratio)
        b = int(top[2] * (1 - ratio) + bottom[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Accent glow spot
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    for i in range(200, 0, -5):
        alpha = int(8 * (i / 200))
        glow_draw.ellipse([width - 500 - i, -100 - i, width - 100 + i, 300 + i], fill=(10, 132, 255, alpha))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(img)

    # Screenshot on the right
    ss_w, ss_h = 720, 450
    screenshot = load_screenshot(ss_w, ss_h)
    ss_x = width - ss_w - 50
    ss_y = (height - ss_h) // 2 + 10

    # Screenshot shadow
    shadow = Image.new("RGBA", (ss_w + 40, ss_h + 40), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((20, 20, ss_w + 20, ss_h + 20), radius=16, fill=(0, 0, 0, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=15))
    # Composite shadow onto full-size canvas at screenshot position
    shadow_canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shadow_canvas.paste(shadow, (ss_x - 20, ss_y - 20))
    img = Image.alpha_composite(img.convert("RGBA"), shadow_canvas).convert("RGB")
    img.paste(screenshot, (ss_x, ss_y))

    draw = ImageDraw.Draw(img)

    # Text on the left
    margin_left = 60
    top_y = 140

    # Logo / brand mark
    draw.rounded_rectangle((margin_left, top_y, margin_left + 44, top_y + 44), radius=10, fill=hex_to_rgb(ACCENT))
    font_icon = get_font(24, bold=True)
    draw.text((margin_left + 13, top_y + 8), "D", font=font_icon, fill=hex_to_rgb(TEXT_PRIMARY))

    # Product name
    font_title = get_font(56, bold=True)
    draw.text((margin_left, top_y + 70), "DbMaster", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))

    # Subtitle
    font_sub = get_font(26)
    draw.text((margin_left, top_y + 150), "AI-Powered Database Manager", font=font_sub, fill=hex_to_rgb(TEXT_PRIMARY))

    # Description lines
    font_body = get_font(20)
    lines = [
        "MySQL · PostgreSQL · SQLite · MongoDB",
        "Redis · Doris · TDengine · SQL Server",
    ]
    y = top_y + 210
    for line in lines:
        draw.text((margin_left, y), line, font=font_body, fill=hex_to_rgb(TEXT_SECONDARY))
        y += 34

    # Pricing pills
    pill_y = top_y + 310
    draw.rounded_rectangle((margin_left, pill_y, margin_left + 180, pill_y + 42), radius=21, fill=hex_to_rgb(ACCENT))
    font_pill = get_font(18, bold=True)
    draw.text((margin_left + 20, pill_y + 9), "$99 / year", font=font_pill, fill=hex_to_rgb(TEXT_PRIMARY))

    draw.rounded_rectangle((margin_left + 200, pill_y, margin_left + 390, pill_y + 42), radius=21, outline=hex_to_rgb(BORDER), width=2)
    draw.text((margin_left + 220, pill_y + 9), "$199 lifetime", font=font_pill, fill=hex_to_rgb(TEXT_PRIMARY))

    # Small footer
    font_foot = get_font(16)
    draw.text((margin_left, height - 70), "Desktop app for macOS, Windows & Linux", font=font_foot, fill=hex_to_rgb(TEXT_MUTED))

    out_path = OUT_DIR / "cover-1280x720.png"
    img.save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_thumbnail():
    """Gumroad thumbnail / social square: 600x600."""
    width, height = 600, 600
    img = Image.new("RGB", (width, height), hex_to_rgb(BG))
    draw = ImageDraw.Draw(img)

    # Gradient
    top = hex_to_rgb("#0B0B0E")
    bottom = hex_to_rgb("#111827")
    for y in range(height):
        ratio = y / height
        r = int(top[0] * (1 - ratio) + bottom[0] * ratio)
        g = int(top[1] * (1 - ratio) + bottom[1] * ratio)
        b = int(top[2] * (1 - ratio) + bottom[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Accent ring/glow
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    for i in range(150, 0, -5):
        alpha = int(10 * (i / 150))
        glow_draw.ellipse([width//2 - 200 - i, height//2 - 200 - i, width//2 + 200 + i, height//2 + 200 + i], fill=(10, 132, 255, alpha))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(img)

    # Central app icon card
    card_size = 220
    card_x = (width - card_size) // 2
    card_y = 90
    draw.rounded_rectangle((card_x, card_y, card_x + card_size, card_y + card_size), radius=32, fill=hex_to_rgb(BG_CARD), outline=hex_to_rgb(BORDER), width=2)

    # App icon
    icon_size = 120
    icon_x = card_x + (card_size - icon_size) // 2
    icon_y = card_y + 40
    draw.rounded_rectangle((icon_x, icon_y, icon_x + icon_size, icon_y + icon_size), radius=24, fill=hex_to_rgb(ACCENT))
    font_icon = get_font(64, bold=True)
    draw.text((icon_x + 33, icon_y + 18), "D", font=font_icon, fill=hex_to_rgb(TEXT_PRIMARY))

    # Title
    font_title = get_font(44, bold=True)
    draw.text((width // 2 - 120, card_y + card_size + 40), "DbMaster", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))

    # Subtitle
    font_sub = get_font(20)
    draw.text((width // 2 - 130, card_y + card_size + 100), "AI Database Manager", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    # Pricing
    font_price = get_font(22, bold=True)
    draw.text((width // 2 - 130, card_y + card_size + 160), "$99/yr  ·  $199 lifetime", font=font_price, fill=hex_to_rgb(ACCENT))

    out_path = OUT_DIR / "thumbnail-600x600.png"
    img.save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_pricing_card():
    """Pricing comparison image: 1200x800."""
    width, height = 1200, 800
    img = Image.new("RGB", (width, height), hex_to_rgb(BG))
    draw = ImageDraw.Draw(img)

    # Gradient
    top = hex_to_rgb("#0B0B0E")
    bottom = hex_to_rgb("#0F172A")
    for y in range(height):
        ratio = y / height
        r = int(top[0] * (1 - ratio) + bottom[0] * ratio)
        g = int(top[1] * (1 - ratio) + bottom[1] * ratio)
        b = int(top[2] * (1 - ratio) + bottom[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    draw = ImageDraw.Draw(img)

    # Title
    font_title = get_font(48, bold=True)
    draw.text((width // 2 - 220, 70), "Choose Your License", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(22)
    draw.text((width // 2 - 180, 135), "Pay yearly or own it forever", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    # Card dimensions
    card_w, card_h = 480, 480
    gap = 40
    start_x = (width - (card_w * 2 + gap)) // 2
    card_y = 220

    features = [
        "All Pro features",
        "All 8 database engines",
        "AI SQL assistant",
        "AI query result analysis",
        "Schema diff & sync",
        "Cross-database Data Sync",
    ]

    for idx, (title, price, period, note, highlight) in enumerate([
        ("Annual", "$99", "/ year", "Billed annually. Cancel anytime.", False),
        ("Lifetime", "$199", " one-time", "All future updates included.", True),
    ]):
        x = start_x + idx * (card_w + gap)
        fill = hex_to_rgb(ACCENT) if highlight else hex_to_rgb(BG_CARD)
        outline = hex_to_rgb(ACCENT) if highlight else hex_to_rgb(BORDER)

        # Card background
        draw.rounded_rectangle((x, card_y, x + card_w, card_y + card_h), radius=20, fill=hex_to_rgb(BG_CARD), outline=outline, width=3)

        # Header bar for highlighted card
        if highlight:
            draw.rounded_rectangle((x, card_y, x + card_w, card_y + 8), radius=20, fill=hex_to_rgb(ACCENT))
            # Popular badge
            badge_w, badge_h = 110, 32
            draw.rounded_rectangle((x + card_w - badge_w - 20, card_y + 20, x + card_w - 20, card_y + 20 + badge_h), radius=16, fill=hex_to_rgb(ACCENT))
            font_badge = get_font(16, bold=True)
            draw.text((x + card_w - badge_w - 5, card_y + 25), "POPULAR", font=font_badge, fill=hex_to_rgb(TEXT_PRIMARY))

        # Plan name
        font_name = get_font(32, bold=True)
        draw.text((x + 40, card_y + 50), title, font=font_name, fill=hex_to_rgb(TEXT_PRIMARY))

        # Price
        font_price = get_font(56, bold=True)
        draw.text((x + 40, card_y + 110), price, font=font_price, fill=hex_to_rgb(TEXT_PRIMARY))
        font_period = get_font(24)
        bbox = draw.textbbox((0, 0), price, font=font_price)
        price_w = bbox[2] - bbox[0]
        draw.text((x + 40 + price_w + 10, card_y + 135), period, font=font_period, fill=hex_to_rgb(TEXT_SECONDARY))

        # Features
        font_feat = get_font(20)
        y_feat = card_y + 200
        for feat in features:
            # Draw checkmark manually since Segoe UI may not render ✓
            cx, cy = x + 46, y_feat + 12
            draw.line([(cx - 5, cy), (cx - 1, cy + 5), (cx + 7, cy - 5)], fill=hex_to_rgb(CHECK_GREEN), width=3)
            draw.text((x + 70, y_feat), feat, font=font_feat, fill=hex_to_rgb(TEXT_SECONDARY))
            y_feat += 34

        # Note
        font_note = get_font(16)
        draw.text((x + 40, card_y + card_h - 45), note, font=font_note, fill=hex_to_rgb(TEXT_MUTED))

    out_path = OUT_DIR / "pricing-1200x800.png"
    img.save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_features_card():
    """Feature highlight image: 1200x1050."""
    width, height = 1200, 1050
    img = Image.new("RGB", (width, height), hex_to_rgb(BG))
    draw = ImageDraw.Draw(img)

    # Gradient
    top = hex_to_rgb("#0B0B0E")
    bottom = hex_to_rgb("#0F172A")
    for y in range(height):
        ratio = y / height
        r = int(top[0] * (1 - ratio) + bottom[0] * ratio)
        g = int(top[1] * (1 - ratio) + bottom[1] * ratio)
        b = int(top[2] * (1 - ratio) + bottom[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    draw = ImageDraw.Draw(img)

    # Title
    font_title = get_font(46, bold=True)
    draw.text((width // 2 - 260, 60), "Everything You Need", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(22)
    draw.text((width // 2 - 180, 120), "One app. Eight database engines. AI inside.", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    # Feature grid: 2 columns x 4 rows
    features = [
        ("AI SQL Assistant", "Ask naturally, get executable SQL, explanations, and optimization tips."),
        ("AI Query Result Analysis", "Click \"AI Analyze\" on any result tab for performance & index insights."),
        ("Smart Query Editor", "Syntax highlighting, autocomplete, formatting, and EXPLAIN visualization."),
        ("Visual Schema Tools", "ER diagrams, table designer, DDL impact & rollback scripts."),
        ("Schema Diff & Sync", "Compare two database schemas and generate migration DDL."),
        ("Cross-Database Data Sync", "Sync rows across engines with truncate, append, replace, or upsert."),
        ("Data Import & Export", "5-step wizard, SQL INSERT export, CSV output."),
        ("Query History & Audit", "Full-text search, filtering, and tamper-aware audit log."),
    ]

    card_w, card_h = 520, 160
    gap_x, gap_y = 40, 24
    start_x = (width - (card_w * 2 + gap_x)) // 2
    start_y = 180

    font_name = get_font(24, bold=True)
    font_desc = get_font(18)

    for i, (name, desc) in enumerate(features):
        col = i % 2
        row = i // 2
        x = start_x + col * (card_w + gap_x)
        y = start_y + row * (card_h + gap_y)

        draw.rounded_rectangle((x, y, x + card_w, y + card_h), radius=16, fill=hex_to_rgb(BG_CARD), outline=hex_to_rgb(BORDER), width=1)

        # Accent dot
        draw.rounded_rectangle((x + 24, y + 28, x + 24 + 12, y + 28 + 12), radius=6, fill=hex_to_rgb(ACCENT))

        # Name
        draw.text((x + 48, y + 22), name, font=font_name, fill=hex_to_rgb(TEXT_PRIMARY))

        # Description (wrap roughly)
        words = desc.split()
        lines = []
        line = ""
        for word in words:
            test = line + " " + word if line else word
            bbox = draw.textbbox((0, 0), test, font=font_desc)
            if bbox[2] - bbox[0] <= card_w - 70:
                line = test
            else:
                if line:
                    lines.append(line)
                line = word
        if line:
            lines.append(line)

        line_y = y + 62
        for line in lines:
            draw.text((x + 24, line_y), line, font=font_desc, fill=hex_to_rgb(TEXT_SECONDARY))
            line_y += 26

    out_path = OUT_DIR / "features-1200x1050.png"
    img.save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


def create_ai_features_card():
    """Dedicated AI feature highlight image: 1200x650."""
    width, height = 1200, 650
    img = Image.new("RGB", (width, height), hex_to_rgb(BG))
    draw = ImageDraw.Draw(img)

    # Gradient
    top = hex_to_rgb("#0B0B0E")
    bottom = hex_to_rgb("#0F172A")
    for y in range(height):
        ratio = y / height
        r = int(top[0] * (1 - ratio) + bottom[0] * ratio)
        g = int(top[1] * (1 - ratio) + bottom[1] * ratio)
        b = int(top[2] * (1 - ratio) + bottom[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    draw = ImageDraw.Draw(img)

    # Title
    font_title = get_font(46, bold=True)
    draw.text((width // 2 - 180, 60), "AI Built In", font=font_title, fill=hex_to_rgb(TEXT_PRIMARY))
    font_sub = get_font(22)
    draw.text((width // 2 - 190, 120), "Ask, analyze, optimize — without leaving the app.", font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY))

    features = [
        ("AI SQL Assistant", "Write or explain SQL in plain language."),
        ("AI Query Result Analysis", "Get performance, index, and error diagnostics from any result tab."),
        ("Slash Commands", "/optimize · /explain · /analyze · /generate for instant help."),
    ]

    card_w, card_h = 340, 360
    gap_x = 40
    start_x = (width - (card_w * 3 + gap_x * 2)) // 2
    card_y = 200

    font_name = get_font(24, bold=True)
    font_desc = get_font(18)

    for i, (name, desc) in enumerate(features):
        x = start_x + i * (card_w + gap_x)
        draw.rounded_rectangle((x, card_y, x + card_w, card_y + card_h), radius=20, fill=hex_to_rgb(BG_CARD), outline=hex_to_rgb(BORDER), width=1)

        # AI icon circle
        cx, cy = x + card_w // 2, card_y + 70
        draw.ellipse((cx - 32, cy - 32, cx + 32, cy + 32), fill=hex_to_rgb(ACCENT))
        font_icon = get_font(28, bold=True)
        label = "AI" if i < 2 else "/"
        bbox = draw.textbbox((0, 0), label, font=font_icon)
        tw = bbox[2] - bbox[0]
        draw.text((cx - tw // 2, cy - 16), label, font=font_icon, fill=hex_to_rgb(TEXT_PRIMARY))

        # Name
        bbox = draw.textbbox((0, 0), name, font=font_name)
        tw = bbox[2] - bbox[0]
        draw.text((x + (card_w - tw) // 2, card_y + 130), name, font=font_name, fill=hex_to_rgb(TEXT_PRIMARY))

        # Description
        words = desc.split()
        lines = []
        line = ""
        for word in words:
            test = line + " " + word if line else word
            bbox = draw.textbbox((0, 0), test, font=font_desc)
            if bbox[2] - bbox[0] <= card_w - 50:
                line = test
            else:
                if line:
                    lines.append(line)
                line = word
        if line:
            lines.append(line)

        line_y = card_y + 180
        for line in lines:
            bbox = draw.textbbox((0, 0), line, font=font_desc)
            tw = bbox[2] - bbox[0]
            draw.text((x + (card_w - tw) // 2, line_y), line, font=font_desc, fill=hex_to_rgb(TEXT_SECONDARY))
            line_y += 28

    out_path = OUT_DIR / "ai-features-1200x650.png"
    img.save(out_path, "PNG", optimize=True)
    print(f"Created: {out_path}")


if __name__ == "__main__":
    print("Generating Gumroad assets for DbMaster...")
    create_cover()
    create_thumbnail()
    create_pricing_card()
    create_features_card()
    create_ai_features_card()
    print("Done. Check assets/gumroad/")
