#!/usr/bin/env python3
"""
VoiceScheduler Splash Screen Generator
프리미엄 골드 테마 스플래시
"""

from PIL import Image, ImageDraw
import math
import os

def create_splash_image(width=400, height=400):
    """스플래시 로고 이미지 생성"""

    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 프리미엄 골드 컬러
    gold = (212, 175, 55)
    gold_light = (240, 210, 120)

    cx, cy = width // 2, height // 2
    size = min(width, height)

    # === 골드 원형 링 ===
    ring_outer = int(size * 0.45)
    ring_inner = int(size * 0.39)

    for w in range(3):
        draw.ellipse([cx - ring_outer + w, cy - ring_outer + w,
                      cx + ring_outer - w, cy + ring_outer - w],
                     outline=gold, width=2)
        draw.ellipse([cx - ring_inner + w, cy - ring_inner + w,
                      cx + ring_inner - w, cy + ring_inner - w],
                     outline=gold, width=2)

    # === 시계 바늘 (10:10) ===
    hour_angle = math.radians(-60)
    hour_len = int(size * 0.17)
    hx = cx + int(hour_len * math.cos(hour_angle))
    hy = cy + int(hour_len * math.sin(hour_angle))
    draw.line([(cx, cy), (hx, hy)], fill=gold, width=int(size * 0.03))

    min_angle = math.radians(-30)
    min_len = int(size * 0.24)
    mx = cx + int(min_len * math.cos(min_angle))
    my = cy + int(min_len * math.sin(min_angle))
    draw.line([(cx, cy), (mx, my)], fill=gold, width=int(size * 0.022))

    # 중심점
    dot_r = int(size * 0.028)
    draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=gold_light)

    # === 12시간 마커 ===
    marker_r = int(size * 0.32)
    for i in range(12):
        angle = math.radians(i * 30 - 90)
        mx = cx + int(marker_r * math.cos(angle))
        my = cy + int(marker_r * math.sin(angle))

        if i % 3 == 0:
            dot_size = int(size * 0.015)
            draw.ellipse([mx - dot_size, my - dot_size,
                          mx + dot_size, my + dot_size], fill=gold_light)
        else:
            dot_size = int(size * 0.008)
            draw.ellipse([mx - dot_size, my - dot_size,
                          mx + dot_size, my + dot_size], fill=gold)

    # === 마이크 아이콘 (하단) ===
    mic_y = cy + int(size * 0.32)
    mic_w = int(size * 0.065)
    mic_h = int(size * 0.10)

    draw.rounded_rectangle([cx - mic_w, mic_y - mic_h,
                            cx + mic_w, mic_y + int(mic_h * 0.3)],
                           radius=mic_w, fill=gold)

    stand_w = int(size * 0.014)
    stand_top = mic_y + int(mic_h * 0.4)
    stand_bottom = stand_top + int(size * 0.05)
    draw.rectangle([cx - stand_w, stand_top, cx + stand_w, stand_bottom], fill=gold)

    base_w = int(size * 0.05)
    base_h = int(size * 0.014)
    draw.rounded_rectangle([cx - base_w, stand_bottom,
                            cx + base_w, stand_bottom + base_h],
                           radius=base_h//2, fill=gold)

    return img

def save_splash_assets(output_dir):
    """스플래시 이미지셋 저장"""

    os.makedirs(output_dir, exist_ok=True)

    # 다양한 해상도
    sizes = [
        (200, "splash_logo.png"),
        (400, "splash_logo@2x.png"),
        (600, "splash_logo@3x.png"),
    ]

    for size, filename in sizes:
        img = create_splash_image(size, size)
        img.save(os.path.join(output_dir, filename), 'PNG')
        print(f"  ✓ {filename}")

    # Contents.json
    contents = {
        "images": [
            {"idiom": "universal", "filename": "splash_logo.png", "scale": "1x"},
            {"idiom": "universal", "filename": "splash_logo@2x.png", "scale": "2x"},
            {"idiom": "universal", "filename": "splash_logo@3x.png", "scale": "3x"}
        ],
        "info": {"version": 1, "author": "xcode"}
    }

    import json
    with open(os.path.join(output_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)
    print("  ✓ Contents.json")

def create_background_color(output_dir):
    """배경색 컬러셋 생성"""

    os.makedirs(output_dir, exist_ok=True)

    # 네이비 배경색
    contents = {
        "colors": [
            {
                "color": {
                    "color-space": "srgb",
                    "components": {
                        "red": "0.059",
                        "green": "0.078",
                        "blue": "0.157",
                        "alpha": "1.000"
                    }
                },
                "idiom": "universal"
            }
        ],
        "info": {"version": 1, "author": "xcode"}
    }

    import json
    with open(os.path.join(output_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)
    print("  ✓ SplashBackground colorset")

if __name__ == "__main__":
    print("✨ 스플래시 스크린 생성 중...")
    print()

    assets_dir = "VoiceScheduler/Assets.xcassets"

    print("📁 스플래시 로고 저장 중...")
    save_splash_assets(f"{assets_dir}/SplashLogo.imageset")

    print()
    print("🎨 배경색 생성 중...")
    create_background_color(f"{assets_dir}/SplashBackground.colorset")

    print()
    print("✅ 스플래시 에셋 생성 완료!")
