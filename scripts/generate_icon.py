#!/usr/bin/env python3
"""
Generate SafeThink app icon - Privacy-first AI assistant
Design: Shield with neural/brain pattern on gradient background
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import os

# Render at 4x for high quality anti-aliasing
RENDER_SIZE = 4096
FINAL_SIZE = 1024

def create_gradient(size, color1, color2, direction='radial'):
    """Create a gradient image."""
    img = Image.new('RGBA', (size, size))
    pixels = img.load()
    cx, cy = size // 2, size // 2
    max_dist = math.sqrt(cx**2 + cy**2)

    for y in range(size):
        for x in range(size):
            if direction == 'radial':
                dist = math.sqrt((x - cx)**2 + (y - cy)**2) / max_dist
            else:  # diagonal
                dist = (x + y) / (2 * size)

            dist = min(1.0, max(0.0, dist))
            r = int(color1[0] + (color2[0] - color1[0]) * dist)
            g = int(color1[1] + (color2[1] - color1[1]) * dist)
            b = int(color1[2] + (color2[2] - color1[2]) * dist)
            a = int(color1[3] + (color2[3] - color1[3]) * dist) if len(color1) > 3 else 255
            pixels[x, y] = (r, g, b, a)

    return img


def draw_rounded_rect(draw, bbox, radius, fill=None, outline=None, width=1):
    """Draw a rounded rectangle."""
    x1, y1, x2, y2 = bbox
    draw.rounded_rectangle(bbox, radius=radius, fill=fill, outline=outline, width=width)


def draw_shield(draw, cx, cy, w, h, fill=None, outline=None, width=1):
    """Draw a shield shape using polygon."""
    # Shield: rounded top rectangle tapering to a point at bottom
    points = []

    # Top-left corner (rounded)
    corner_r = w * 0.15
    top = cy - h * 0.5
    bottom = cy + h * 0.5
    left = cx - w * 0.5
    right = cx + w * 0.5

    # Generate shield outline points
    steps = 40

    # Top-left corner arc
    for i in range(steps + 1):
        angle = math.pi + (math.pi / 2) * (i / steps)
        px = left + corner_r + corner_r * math.cos(angle)
        py = top + corner_r + corner_r * math.sin(angle)
        points.append((px, py))

    # Top-right corner arc
    for i in range(steps + 1):
        angle = -math.pi / 2 + (math.pi / 2) * (i / steps)
        px = right - corner_r + corner_r * math.cos(angle)
        py = top + corner_r + corner_r * math.sin(angle)
        points.append((px, py))

    # Right side curves down to bottom point
    mid_y = cy + h * 0.1
    for i in range(steps + 1):
        t = i / steps
        # Bezier-like curve from right side to bottom point
        px = right * (1 - t**1.5) + cx * t**1.5
        py = mid_y * (1 - t) + bottom * t
        points.append((px, py))

    # Bottom point to left side
    for i in range(steps + 1):
        t = i / steps
        px = cx * (1 - t) + left * t**1.5
        py = bottom * (1 - t) + mid_y * t
        points.append((px, py))

    if fill:
        draw.polygon(points, fill=fill)
    if outline:
        draw.polygon(points, outline=outline)
        # Draw thicker outline
        if width > 1:
            for i in range(len(points)):
                p1 = points[i]
                p2 = points[(i + 1) % len(points)]
                draw.line([p1, p2], fill=outline, width=width)


def draw_brain_circuit(draw, cx, cy, size, color, glow_color):
    """Draw a stylized brain/neural network pattern."""
    # Define neural network nodes
    nodes = [
        # Left hemisphere
        (cx - size * 0.22, cy - size * 0.25),
        (cx - size * 0.30, cy - size * 0.08),
        (cx - size * 0.25, cy + size * 0.10),
        (cx - size * 0.15, cy + size * 0.22),
        (cx - size * 0.10, cy - size * 0.15),

        # Right hemisphere
        (cx + size * 0.22, cy - size * 0.25),
        (cx + size * 0.30, cy - size * 0.08),
        (cx + size * 0.25, cy + size * 0.10),
        (cx + size * 0.15, cy + size * 0.22),
        (cx + size * 0.10, cy - size * 0.15),

        # Center
        (cx, cy - size * 0.30),
        (cx, cy),
        (cx, cy + size * 0.15),
        (cx - size * 0.05, cy - size * 0.05),
        (cx + size * 0.05, cy - size * 0.05),
    ]

    # Define connections between nodes
    connections = [
        (0, 1), (1, 2), (2, 3), (0, 4), (4, 11),
        (5, 6), (6, 7), (7, 8), (5, 9), (9, 11),
        (0, 10), (5, 10), (10, 13), (10, 14),
        (13, 11), (14, 11), (11, 12),
        (3, 12), (8, 12),
        (1, 13), (6, 14),
        (4, 13), (9, 14),
        (2, 12), (7, 12),
    ]

    # Draw connections (lines)
    line_width = int(size * 0.012)
    for i, j in connections:
        draw.line([nodes[i], nodes[j]], fill=color, width=line_width)

    # Draw nodes (circles)
    node_sizes = []
    for idx, (nx, ny) in enumerate(nodes):
        if idx in (10, 11, 12):  # Center nodes are larger
            r = size * 0.030
        else:
            r = size * 0.022
        node_sizes.append(r)

        # Glow effect
        glow_r = r * 2.0
        draw.ellipse(
            [nx - glow_r, ny - glow_r, nx + glow_r, ny + glow_r],
            fill=glow_color
        )

    # Draw actual nodes on top
    for idx, (nx, ny) in enumerate(nodes):
        r = node_sizes[idx]
        draw.ellipse(
            [nx - r, ny - r, nx + r, ny + r],
            fill=color
        )


def draw_lock_icon(draw, cx, cy, size, color):
    """Draw a small lock icon."""
    w = size * 0.10
    h = size * 0.08

    # Lock body (rounded rectangle)
    body_x1 = cx - w/2
    body_y1 = cy
    body_x2 = cx + w/2
    body_y2 = cy + h
    draw.rounded_rectangle(
        [body_x1, body_y1, body_x2, body_y2],
        radius=size * 0.012,
        fill=color
    )

    # Lock shackle (arc)
    shackle_w = w * 0.6
    shackle_h = h * 0.7
    line_w = int(size * 0.014)
    draw.arc(
        [cx - shackle_w/2, cy - shackle_h, cx + shackle_w/2, cy + shackle_h * 0.2],
        start=180, end=0,
        fill=color, width=line_w
    )

    # Keyhole
    kh_r = size * 0.012
    kh_cy = cy + h * 0.35
    # Circle part
    draw.ellipse(
        [cx - kh_r, kh_cy - kh_r, cx + kh_r, kh_cy + kh_r],
        fill=(20, 30, 70, 255)
    )


def generate_icon():
    """Generate the main app icon."""
    S = RENDER_SIZE
    cx, cy = S // 2, S // 2

    # === BACKGROUND ===
    # Rich gradient: deep navy to vibrant blue-purple
    bg = Image.new('RGBA', (S, S), (0, 0, 0, 0))

    # Create multi-stop gradient background
    bg_draw = ImageDraw.Draw(bg)

    # Fill with base dark color
    bg_draw.rectangle([0, 0, S, S], fill=(12, 15, 42, 255))

    # Add radial gradient overlay (brighter center)
    gradient_overlay = create_gradient(
        S,
        (45, 80, 180, 180),   # Bright blue center
        (12, 15, 42, 0),       # Transparent edges
        'radial'
    )
    bg = Image.alpha_composite(bg, gradient_overlay)

    # Add diagonal gradient for depth
    diag_gradient = create_gradient(
        S,
        (30, 50, 140, 100),
        (80, 40, 160, 60),
        'diagonal'
    )
    bg = Image.alpha_composite(bg, diag_gradient)

    # === SHIELD ===
    shield_layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    shield_draw = ImageDraw.Draw(shield_layer)

    shield_w = S * 0.58
    shield_h = S * 0.65
    shield_cy = cy - S * 0.02  # Slightly above center

    # Shield glow (larger, blurred)
    glow_layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    draw_shield(glow_draw, cx, shield_cy, shield_w * 1.08, shield_h * 1.08,
                fill=(60, 130, 255, 40))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=S * 0.03))
    bg = Image.alpha_composite(bg, glow_layer)

    # Shield body with semi-transparent fill
    draw_shield(shield_draw, cx, shield_cy, shield_w, shield_h,
                fill=(20, 35, 80, 200))

    # Shield border
    draw_shield(shield_draw, cx, shield_cy, shield_w, shield_h,
                outline=(100, 160, 255, 200), width=int(S * 0.008))

    # Inner shield border (slightly smaller, subtle)
    draw_shield(shield_draw, cx, shield_cy, shield_w * 0.92, shield_h * 0.92,
                outline=(80, 140, 230, 80), width=int(S * 0.004))

    bg = Image.alpha_composite(bg, shield_layer)

    # === BRAIN/NEURAL NETWORK ===
    brain_layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    brain_draw = ImageDraw.Draw(brain_layer)

    brain_size = S * 0.7
    brain_cy = shield_cy - S * 0.03

    draw_brain_circuit(
        brain_draw, cx, brain_cy, brain_size,
        color=(140, 200, 255, 255),         # Bright cyan-white
        glow_color=(60, 130, 255, 50)       # Blue glow
    )

    # Add glow to brain
    brain_glow = brain_layer.filter(ImageFilter.GaussianBlur(radius=S * 0.008))
    bg = Image.alpha_composite(bg, brain_glow)
    bg = Image.alpha_composite(bg, brain_layer)

    # === LOCK ICON (bottom of shield) ===
    lock_layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    lock_draw = ImageDraw.Draw(lock_layer)

    lock_cy = shield_cy + shield_h * 0.28
    draw_lock_icon(lock_draw, cx, lock_cy, S, (140, 200, 255, 255))

    bg = Image.alpha_composite(bg, lock_layer)

    # === SUBTLE SPARKLE/STARS ===
    sparkle_layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sparkle_draw = ImageDraw.Draw(sparkle_layer)

    sparkles = [
        (cx - S * 0.35, cy - S * 0.35, S * 0.015),
        (cx + S * 0.33, cy - S * 0.30, S * 0.010),
        (cx - S * 0.30, cy + S * 0.30, S * 0.008),
        (cx + S * 0.38, cy + S * 0.25, S * 0.012),
        (cx + S * 0.05, cy - S * 0.42, S * 0.009),
    ]

    for sx, sy, sr in sparkles:
        # Four-pointed star
        for angle in [0, math.pi/2]:
            x1 = sx + math.cos(angle) * sr * 3
            y1 = sy + math.sin(angle) * sr * 3
            x2 = sx - math.cos(angle) * sr * 3
            y2 = sy - math.sin(angle) * sr * 3
            sparkle_draw.line([(x1, y1), (x2, y2)],
                            fill=(200, 220, 255, 120), width=int(sr * 0.5))
        sparkle_draw.ellipse(
            [sx - sr, sy - sr, sx + sr, sy + sr],
            fill=(220, 235, 255, 160)
        )

    sparkle_glow = sparkle_layer.filter(ImageFilter.GaussianBlur(radius=S * 0.005))
    bg = Image.alpha_composite(bg, sparkle_glow)
    bg = Image.alpha_composite(bg, sparkle_layer)

    # === CORNER ROUNDING (iOS style) ===
    # iOS icons use continuous corner radius (~22.37% of icon size)
    # But the OS applies the mask, so we just need a square image
    # For App Store, provide a square image without rounding

    # === FINAL RESIZE ===
    final = bg.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)

    return final


def generate_all_sizes(icon_1024):
    """Generate all required icon sizes for iOS App Store submission."""
    output_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'SafeThink', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset'
    )
    os.makedirs(output_dir, exist_ok=True)

    # For modern Xcode (15+), a single 1024x1024 is sufficient
    # But we'll generate a comprehensive set for maximum compatibility

    # Save the main 1024x1024
    icon_path = os.path.join(output_dir, 'AppIcon-1024x1024.png')
    icon_1024.save(icon_path, 'PNG')
    print(f"  Saved: {icon_path}")

    # Generate Contents.json for single-image approach (Xcode 15+)
    contents = {
        "images": [
            {
                "filename": "AppIcon-1024x1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }

    import json
    contents_path = os.path.join(output_dir, 'Contents.json')
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    print(f"  Saved: {contents_path}")

    # Also generate dark and tinted variants for iOS 18+
    # Dark variant: slightly darker background
    dark_icon = generate_dark_variant(icon_1024)
    dark_path = os.path.join(output_dir, 'AppIcon-Dark-1024x1024.png')
    dark_icon.save(dark_path, 'PNG')
    print(f"  Saved: {dark_path}")

    # Tinted variant: desaturated version for tinting
    tinted_icon = generate_tinted_variant(icon_1024)
    tinted_path = os.path.join(output_dir, 'AppIcon-Tinted-1024x1024.png')
    tinted_icon.save(tinted_path, 'PNG')
    print(f"  Saved: {tinted_path}")

    # Update Contents.json with dark and tinted variants
    contents = {
        "images": [
            {
                "filename": "AppIcon-1024x1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            },
            {
                "appearances": [
                    {
                        "appearance": "luminosity",
                        "value": "dark"
                    }
                ],
                "filename": "AppIcon-Dark-1024x1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            },
            {
                "appearances": [
                    {
                        "appearance": "luminosity",
                        "value": "tinted"
                    }
                ],
                "filename": "AppIcon-Tinted-1024x1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }

    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    print(f"  Updated: {contents_path} (with dark & tinted variants)")

    # Generate App Store marketing icon (separate, without rounding)
    marketing_dir = os.path.join(output_dir, '..', '..', '..', '..', 'AppStoreAssets')
    os.makedirs(marketing_dir, exist_ok=True)
    marketing_path = os.path.join(marketing_dir, 'AppIcon-AppStore-1024x1024.png')
    icon_1024.save(marketing_path, 'PNG')
    print(f"  Saved: {marketing_path}")

    return output_dir


def generate_dark_variant(icon):
    """Generate a darker variant for dark mode."""
    from PIL import ImageEnhance

    # Darken the image
    enhancer = ImageEnhance.Brightness(icon)
    dark = enhancer.enhance(0.75)

    # Increase contrast slightly
    enhancer = ImageEnhance.Contrast(dark)
    dark = enhancer.enhance(1.15)

    return dark


def generate_tinted_variant(icon):
    """Generate a desaturated/monochrome variant for tinted mode."""
    from PIL import ImageEnhance

    # Desaturate
    enhancer = ImageEnhance.Color(icon)
    tinted = enhancer.enhance(0.15)  # Nearly grayscale

    # Adjust brightness
    enhancer = ImageEnhance.Brightness(tinted)
    tinted = enhancer.enhance(0.9)

    # Increase contrast
    enhancer = ImageEnhance.Contrast(tinted)
    tinted = enhancer.enhance(1.2)

    return tinted


if __name__ == '__main__':
    print("Generating SafeThink app icon...")
    print("  Design: Shield + Neural Network (Privacy-first AI)")
    print(f"  Rendering at {RENDER_SIZE}x{RENDER_SIZE}, output at {FINAL_SIZE}x{FINAL_SIZE}")
    print()

    icon = generate_icon()
    print("Icon generated successfully!")
    print()

    print("Saving icon assets...")
    output_dir = generate_all_sizes(icon)
    print()
    print(f"All icons saved to: {output_dir}")
    print("Done!")
