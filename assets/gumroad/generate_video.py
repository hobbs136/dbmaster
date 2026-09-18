#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate a Gumroad promo video (MP4) using real app screenshots and existing assets.
Uses OpenCV (cv2) — no ffmpeg required.
Resolution: 1920x1080, 30fps, ~30 seconds.
"""

import math
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).parent
OUT_PATH = ROOT / "promo-video-1920x1080.mp4"
FPS = 30
WIDTH, HEIGHT = 1920, 1080
DURATION_SECONDS = 30
TOTAL_FRAMES = FPS * DURATION_SECONDS

# Brand colors
BG = "#0B0B0E"
ACCENT = "#0A84FF"
TEXT_PRIMARY = "#FFFFFF"
TEXT_SECONDARY = "#A1A1AA"


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


def make_gradient(width, height):
    top = hex_to_rgb("#0B0B0E")
    bottom = hex_to_rgb("#0F172A")
    arr = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        ratio = y / height
        arr[y, :] = [
            int(top[0] * (1 - ratio) + bottom[0] * ratio),
            int(top[1] * (1 - ratio) + bottom[1] * ratio),
            int(top[2] * (1 - ratio) + bottom[2] * ratio),
        ]
    return arr


def pil_to_cv2(pil_img):
    return cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)


def cv2_to_pil(cv_img):
    return Image.fromarray(cv2.cvtColor(cv_img, cv2.COLOR_BGR2RGB))


def ease_in_out(t):
    return 0.5 - 0.5 * math.cos(t * math.pi)


def load_asset(name):
    return Image.open(ROOT / name).convert("RGB")


def fill_frame_with_image(frame, pil_img, zoom_start=1.0, zoom_end=1.05, pan_x=0, pan_y=0):
    """Scale and crop an image to fill the 1920x1080 frame with slow zoom."""
    img_w, img_h = pil_img.size
    # Determine scale to cover frame while maintaining aspect ratio
    scale = max(WIDTH / img_w, HEIGHT / img_h)

    # progress 0..1 across this scene's frames isn't known here, so we apply fixed zoom
    # Actually caller should handle zoom per frame. Simpler: just center-fit with slight zoom.
    base_zoom = (zoom_start + zoom_end) / 2
    new_w = int(img_w * scale * base_zoom)
    new_h = int(img_h * scale * base_zoom)
    resized = pil_img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    x = (new_w - WIDTH) // 2 + pan_x
    y = (new_h - HEIGHT) // 2 + pan_y
    cropped = resized.crop((x, y, x + WIDTH, y + HEIGHT))
    return pil_to_cv2(cropped)


def frame_with_center_image(frame_idx, scene_start, scene_duration, pil_img, zoom_start=1.0, zoom_end=1.05):
    """Create a frame that centers an image and slowly zooms."""
    progress = (frame_idx - scene_start * FPS) / (scene_duration * FPS)
    progress = max(0.0, min(1.0, progress))
    eased = ease_in_out(progress)
    zoom = zoom_start + (zoom_end - zoom_start) * eased

    img_w, img_h = pil_img.size
    scale = max(WIDTH / img_w, HEIGHT / img_h) * zoom
    new_w = int(img_w * scale)
    new_h = int(img_h * scale)
    resized = pil_img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    x = (new_w - WIDTH) // 2
    y = (new_h - HEIGHT) // 2
    cropped = resized.crop((x, y, x + WIDTH, y + HEIGHT))
    return pil_to_cv2(cropped)


def fade_between(frame_a, frame_b, progress):
    return cv2.addWeighted(frame_a, 1 - progress, frame_b, progress, 0)


# Pre-load assets
cover_img = load_asset("cover-1280x720.png")
db_types_img = load_asset("db-types-1200x800.png")
connection_img = load_asset("connection-management-1200x800.png")
data_sync_img = load_asset("data-sync-1200x800.png")
schema_diff_img = load_asset("schema-diff-1200x800.png")
ai_analysis_img = load_asset("ai-analysis-1200x800.png")
pricing_img = load_asset("pricing-1200x800.png")


def scene_logo(frame_idx):
    frame = make_gradient(WIDTH, HEIGHT)
    progress = frame_idx / (FPS * 2)
    eased = ease_in_out(min(1.0, progress * 1.5))

    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    for i in range(200, 0, -5):
        alpha = int(8 * (i / 200))
        glow_draw.ellipse([WIDTH // 2 - i, HEIGHT // 2 - 200 - i, WIDTH // 2 + i, HEIGHT // 2 - 200 + i], fill=(10, 132, 255, alpha))
    frame = Image.alpha_composite(cv2_to_pil(frame).convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(frame)

    alpha = int(255 * eased)

    # Icon card
    card_size = 220
    card_x = (WIDTH - card_size) // 2
    card_y = 260
    draw.rounded_rectangle((card_x, card_y, card_x + card_size, card_y + card_size), radius=32,
                           fill=hex_to_rgb("#15151A") + (alpha,), outline=hex_to_rgb("#27272A") + (alpha,), width=2)
    icon_size = 120
    icon_x = card_x + (card_size - icon_size) // 2
    icon_y = card_y + 40
    draw.rounded_rectangle((icon_x, icon_y, icon_x + icon_size, icon_y + icon_size), radius=24,
                           fill=hex_to_rgb(ACCENT) + (alpha,))
    font_icon = get_font(64, bold=True)
    draw.text((icon_x + 33, icon_y + 18), "D", font=font_icon, fill=hex_to_rgb(TEXT_PRIMARY) + (alpha,))

    font_title = get_font(56, bold=True)
    bbox = draw.textbbox((0, 0), "DbMaster", font=font_title)
    title_w = bbox[2] - bbox[0]
    draw.text(((WIDTH - title_w) // 2, card_y + card_size + 40), "DbMaster",
              font=font_title, fill=hex_to_rgb(TEXT_PRIMARY) + (alpha,))

    font_sub = get_font(26)
    bbox = draw.textbbox((0, 0), "AI-Powered Database Manager", font=font_sub)
    sub_w = bbox[2] - bbox[0]
    draw.text(((WIDTH - sub_w) // 2, card_y + card_size + 115), "AI-Powered Database Manager",
              font=font_sub, fill=hex_to_rgb(TEXT_SECONDARY) + (alpha,))

    return pil_to_cv2(frame)


def scene_screenshot(frame_idx, scene_start, scene_duration, pil_img, zoom_start=1.0, zoom_end=1.05):
    return frame_with_center_image(frame_idx, scene_start, scene_duration, pil_img, zoom_start, zoom_end)


def scene_pricing(frame_idx, scene_start, scene_duration):
    return frame_with_center_image(frame_idx, scene_start, scene_duration, pricing_img, 1.0, 1.04)


def scene_cta(frame_idx, scene_start, scene_duration):
    frame = make_gradient(WIDTH, HEIGHT)
    progress = (frame_idx - scene_start * FPS) / (scene_duration * FPS)
    progress = max(0.0, min(1.0, progress))
    eased = ease_in_out(min(1.0, progress * 1.5))

    pil = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(pil)
    alpha = int(255 * eased)

    font_title = get_font(60, bold=True)
    bbox = draw.textbbox((0, 0), "Manage every database", font=font_title)
    title_w = bbox[2] - bbox[0]
    draw.text(((WIDTH - title_w) // 2, 300), "Manage every database",
              font=font_title, fill=hex_to_rgb(TEXT_PRIMARY) + (alpha,))

    bbox = draw.textbbox((0, 0), "from one powerful app", font=font_title)
    title_w = bbox[2] - bbox[0]
    draw.text(((WIDTH - title_w) // 2, 380), "from one powerful app",
              font=font_title, fill=hex_to_rgb(TEXT_PRIMARY) + (alpha,))

    font_sub = get_font(30)
    bbox = draw.textbbox((0, 0), "$99/year  ·  $199 lifetime", font=font_sub)
    sub_w = bbox[2] - bbox[0]
    draw.text(((WIDTH - sub_w) // 2, 490), "$99/year  ·  $199 lifetime",
              font=font_sub, fill=hex_to_rgb(ACCENT) + (alpha,))

    btn_w, btn_h = 280, 64
    btn_x = (WIDTH - btn_w) // 2
    btn_y = 590
    draw.rounded_rectangle((btn_x, btn_y, btn_x + btn_w, btn_y + btn_h), radius=32,
                           fill=hex_to_rgb(ACCENT) + (alpha,))
    font_btn = get_font(24, bold=True)
    bbox = draw.textbbox((0, 0), "Get DbMaster", font=font_btn)
    text_w = bbox[2] - bbox[0]
    draw.text((btn_x + (btn_w - text_w) // 2, btn_y + 16), "Get DbMaster",
              font=font_btn, fill=hex_to_rgb(TEXT_PRIMARY) + (alpha,))

    frame = Image.alpha_composite(cv2_to_pil(frame).convert("RGBA"), pil)
    return pil_to_cv2(frame.convert("RGB"))


# Scene config: (start_second, duration, image_asset_or_none, zoom_start, zoom_end)
SCENES = [
    (0, 2, None, 1.0, 1.0),             # Logo
    (2, 3, db_types_img, 1.0, 1.03),    # 8 DB types
    (3, 3, connection_img, 1.0, 1.03),  # Connection management
    (6, 4, data_sync_img, 1.0, 1.03),   # Data Sync
    (10, 4, schema_diff_img, 1.0, 1.03), # Schema Diff
    (14, 4, ai_analysis_img, 1.0, 1.03), # AI Analysis
    (18, 4, cover_img, 1.0, 1.02),      # Product cover
    (22, 4, None, 1.0, 1.0),            # Pricing (handled specially)
    (26, 4, None, 1.0, 1.0),            # CTA (handled specially)
]


def build_video():
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(OUT_PATH), fourcc, FPS, (WIDTH, HEIGHT))
    if not writer.isOpened():
        raise RuntimeError("Could not open video writer")

    prev_frame = None
    current_frame = None

    for frame_idx in range(TOTAL_FRAMES):
        second = frame_idx / FPS

        # Determine active scene
        scene_idx = 0
        for i, (start, duration, _, _, _) in enumerate(SCENES):
            if second >= start:
                scene_idx = i

        scene_start, scene_duration, asset, zoom_start, zoom_end = SCENES[scene_idx]

        if scene_idx == 0:
            current_frame = scene_logo(frame_idx)
        elif scene_idx == 7:
            current_frame = scene_pricing(frame_idx, scene_start, scene_duration)
        elif scene_idx == 8:
            current_frame = scene_cta(frame_idx, scene_start, scene_duration)
        else:
            current_frame = scene_screenshot(frame_idx, scene_start, scene_duration, asset, zoom_start, zoom_end)

        # Crossfade at scene boundaries (0.4s transition)
        transition_frames = int(FPS * 0.4)
        local_idx = frame_idx - scene_start * FPS
        if prev_frame is not None and local_idx < transition_frames and scene_idx > 0:
            t = local_idx / transition_frames
            frame = fade_between(prev_frame, current_frame, t)
        else:
            frame = current_frame

        # Update prev_frame at end of scene
        if local_idx == scene_duration * FPS - 1:
            prev_frame = current_frame.copy()

        writer.write(frame)

    writer.release()
    print(f"Created: {OUT_PATH}")


if __name__ == "__main__":
    print("Generating promo video from real screenshots...")
    build_video()
    print("Done.")
