#!/usr/bin/env python3
"""Build the app icon, its recoloured alternates, the launch mark and README mascot from mascot-icon.png.

Run from the repository root: docs/design/brand/make-icons.py
The alternate icons without the mascot are drawn by make-drawn-icons.swift; run that first.
The painted icons' dark and tinted pictures need the subject masks in masks/ (make-subject-masks.swift).
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

CATALOG = "app/DshIOS/Assets.xcassets/"


def rounded(image, size):
    """The drawing on a transparent canvas with the icon's corners, for use outside the app icon."""
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), size, fill=255)
    result = image.resize((size, size), Image.LANCZOS).convert("RGBA")
    result.putalpha(mask.resize((size, size), Image.LANCZOS))
    return result


def subject_mask(name):
    """How much of each pixel belongs to the subject, from masks/ (make-subject-masks.swift)."""
    return Image.open(f"docs/design/brand/masks/{name}.png").convert("L").resize((1024, 1024), Image.LANCZOS)


def without_background(picture, mask):
    """The picture's colours with the background taken out of the half-covered edge pixels, so the
    cut-out shows no light rim on a dark backdrop. The background behind each edge is estimated from
    the nearby pixels that are all background."""
    pixels = np.asarray(picture).astype(np.float32)
    alpha = np.asarray(mask).astype(np.float32)[..., None] / 255
    behind = (alpha < 0.05).astype(np.float32)
    blur = lambda array: np.asarray(Image.fromarray(array).filter(ImageFilter.GaussianBlur(12))).astype(np.float32)
    weight = blur((behind[..., 0] * 255).astype(np.uint8))[..., None] / 255
    background = np.stack([blur((pixels[..., c] * behind[..., 0]).astype(np.uint8)) for c in range(3)], -1)
    background = np.where(weight > 0.01, background / np.maximum(weight, 0.01), pixels)
    cleaned = (pixels - (1 - alpha) * background) / np.maximum(alpha, 0.05)
    edge = (alpha > 0.02) & (alpha < 0.98)
    return np.clip(np.where(edge, cleaned, pixels), 0, 255).round().astype(np.uint8)


def save_appearances(picture, mask, folder, flat=False):
    """Light: the picture as it is. Dark: the subject on nothing, so the system's dark backdrop
    replaces the light background. Tinted: the subject in grey on nothing, which the system tints.

    The tinted grey follows the picture's own light and shade, lifted so the darkest parts still take
    some tint. A flat drawing (one colour with a few light details) instead turns its colour white and
    its light details clear, like the drawn icons.
    """
    picture.save(folder + "AppIcon.png", optimize=True)
    if flat:
        # Subject lifting keeps only the biggest shape (the whale, not its spout), so a flat drawing
        # also keeps whatever stands apart from its plain background colour.
        pixels = np.asarray(picture).astype(np.float32)
        distance = np.linalg.norm(pixels - pixels[8, 8], axis=-1)
        ink = np.clip((distance - 30) / 30, 0, 1) * 255
        mask = Image.fromarray(np.maximum(np.asarray(mask), ink).astype(np.uint8), "L")
    dark = Image.fromarray(np.dstack([without_background(picture, mask), np.asarray(mask)]), "RGBA")
    dark.save(folder + "AppIcon-Dark.png", optimize=True)
    lightness = np.asarray(picture.convert("L")).astype(np.float32) / 255
    alpha = np.asarray(mask).astype(np.float32) / 255
    if flat:
        grey = np.clip((0.8 - lightness) / 0.3, 0, 1)
    else:
        low, high = np.percentile(lightness[alpha > 0.9], [2, 98])
        grey = 0.3 + 0.7 * np.clip((lightness - low) / (high - low), 0, 1)
    tinted = np.stack([grey * 255, alpha * 255], -1).round().astype(np.uint8)
    Image.fromarray(tinted, "LA").save(folder + "AppIcon-Tinted.png", optimize=True)


icon = Image.open("docs/design/brand/mascot-icon.png").convert("RGB").resize((1024, 1024), Image.LANCZOS)
icons = CATALOG + "AppIcon.appiconset/"
mascot_mask = subject_mask("mascot")
save_appearances(icon, mascot_mask, icons)
icon.resize((192, 192), Image.LANCZOS).save("docs/assets/icon.png", optimize=True)
rounded(icon, 640).save("docs/assets/mascot.png", optimize=True)


def recolored(image, hue, saturation=1.0):
    """The blues (hair, eyes, bows, background) turned to another hue; skin and whites stay.

    The shift fades out towards the edges of the blue band, so the colours meet without seams.
    """
    hsv = np.asarray(image.convert("HSV")).astype(np.float32)
    h, s, v = hsv[..., 0] * 360 / 255, hsv[..., 1], hsv[..., 2]
    distance = np.abs((h - 225 + 180) % 360 - 180)
    weight = np.clip((70 - distance) / 25, 0, 1)
    h = (h + (hue - 225) * weight) % 360
    s = np.clip(s * (1 + (saturation - 1) * weight), 0, 255)
    pixels = np.stack([h * 255 / 360, s, v], -1).round().astype(np.uint8)
    return Image.fromarray(pixels, "HSV").convert("RGB")


def preview(image, name):
    """The picture the icon page shows (app icon sets cannot be loaded as images): 60 pt at 3x."""
    image.resize((180, 180), Image.LANCZOS).save(CATALOG + f"AppIconPreview/{name}.imageset/{name}.png", optimize=True)


preview(icon, "Default")

# The alternate icons people can pick in Settings (app/DshIOS/Views/AppIconPage.swift).
for name, hue, saturation in [("Pink", 335, 0.9), ("Mint", 165, 0.85), ("Violet", 275, 1.0)]:
    folder = CATALOG + f"AppIcon-{name}.appiconset/"
    variant = recolored(icon, hue, saturation)
    save_appearances(variant, mascot_mask, folder)
    preview(variant, name)

# Drawn by make-drawn-icons.swift and make-wordmark-icons.swift, run first.
for name in ["Whale", "WordPixel", "WordPoster", "WordMono"]:
    preview(Image.open(CATALOG + f"AppIcon-{name}.appiconset/AppIcon.png").convert("RGB"), name)

# Made with an image model (Codex image generation) and kept as they came in generated/:
# a geometric whale, a pixel-art whale, and a sticker of the mascot.
for name, source in [("Geometric", "geometric"), ("Pixel", "pixel"), ("Sticker", "sticker")]:
    folder = CATALOG + f"AppIcon-{name}.appiconset/"
    picture = Image.open(f"docs/design/brand/generated/{source}.png").convert("RGB").resize((1024, 1024), Image.LANCZOS)
    if name == "Pixel":
        # Already a night sky: the same picture works on a dark home screen, and in grey its sky is
        # near black, so only the whale and the stars take the tint.
        picture.save(folder + "AppIcon.png", optimize=True)
        picture.save(folder + "AppIcon-Dark.png", optimize=True)
        ImageOps.grayscale(picture).save(folder + "AppIcon-Tinted.png", optimize=True)
    else:
        save_appearances(picture, subject_mask(source), folder, flat=name == "Geometric")
    preview(picture, name)

for scale, suffix in [(2, "@2x"), (3, "@3x")]:
    mark = rounded(icon, 72 * scale)
    mark.save(CATALOG + f"LaunchMark.imageset/LaunchMark{suffix}.png", optimize=True)
    mark.save(CATALOG + f"LaunchMark.imageset/LaunchMark-Dark{suffix}.png", optimize=True)
