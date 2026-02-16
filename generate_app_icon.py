#!/usr/bin/env python3
"""
VoiceScheduler App Icon Generator
캘린더 + 마이크 골드 디자인 - 굵은 스케줄 선
"""

from PIL import Image, ImageDraw
import math
import os

def create_app_icon(size=1024):
    """앱 아이콘 생성 - 캘린더 + 마이크 골드"""

    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 컬러 팔레트
    deep_navy = (15, 20, 40)
    navy_mid = (25, 35, 65)
    gold = (218, 175, 75)
    gold_alpha = (218, 175, 75, 240)
    gold_line = (218, 175, 75, 160)
    gold_header = (235, 215, 160)
    white = (255, 255, 255)

    corner_radius = int(size * 0.22)
    cx, cy = size // 2, size // 2

    # === 배경 - 깊은 네이비 그라데이션 ===
    for y in range(size):
        ratio = y / size
        r = int(deep_navy[0] + (navy_mid[0] - deep_navy[0]) * ratio)
        g = int(deep_navy[1] + (navy_mid[1] - deep_navy[1]) * ratio)
        b = int(deep_navy[2] + (navy_mid[2] - deep_navy[2]) * ratio)
        draw.line([(0, y), (size, y)], fill=(r, g, b))

    # 라운드 마스크 적용
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, size, size], radius=corner_radius, fill=255)

    bg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bg.paste(img, mask=mask)
    img = bg
    draw = ImageDraw.Draw(img)

    # === 캘린더 프레임 ===
    cal_margin = int(size * 0.1)
    cal_left = cal_margin
    cal_right = size - cal_margin
    cal_top = int(size * 0.08)
    cal_bottom = int(size * 0.92)
    cal_radius = int(size * 0.06)
    cal_stroke = int(size * 0.01)  # 10px at 1024

    # 캘린더 외곽선
    draw.rounded_rectangle(
        [cal_left, cal_top, cal_right, cal_bottom],
        radius=cal_radius,
        outline=gold_alpha,
        width=cal_stroke
    )

    # === 캘린더 헤더 (상단 영역) ===
    header_height = int(size * 0.12)
    header_bottom = cal_top + header_height

    # 헤더 배경 채우기
    header_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    header_draw = ImageDraw.Draw(header_img)
    header_draw.rounded_rectangle(
        [cal_left + cal_stroke, cal_top + cal_stroke,
         cal_right - cal_stroke, header_bottom],
        radius=max(cal_radius - cal_stroke, 1),
        fill=gold_header
    )
    # 하단 모서리를 직각으로 채우기
    header_draw.rectangle(
        [cal_left + cal_stroke, header_bottom - cal_radius,
         cal_right - cal_stroke, header_bottom],
        fill=gold_header
    )
    img = Image.alpha_composite(img, header_img)
    draw = ImageDraw.Draw(img)

    # 헤더 구분선
    divider_y = header_bottom
    draw.line(
        [(cal_left, divider_y), (cal_right, divider_y)],
        fill=gold_alpha,
        width=int(size * 0.007)
    )

    # 요일 표시 도트 (7개)
    dot_y = cal_top + header_height // 2
    dot_area_left = cal_left + int(size * 0.08)
    dot_area_right = cal_right - int(size * 0.08)
    dot_spacing = (dot_area_right - dot_area_left) / 6
    dot_r = int(size * 0.009)

    for i in range(7):
        dx = int(dot_area_left + i * dot_spacing)
        draw.ellipse(
            [dx - dot_r, dot_y - dot_r, dx + dot_r, dot_y + dot_r],
            fill=(200, 160, 60)
        )

    # === 스케줄 선 (3개 - 굵게!) ===
    body_top = header_bottom + int(size * 0.04)
    body_bottom = cal_bottom - int(size * 0.04)
    body_height = body_bottom - body_top
    line_width = int(size * 0.012)  # 12px at 1024 - 더 굵게!

    line_positions = [0.22, 0.50, 0.78]  # 상단, 중앙, 하단
    for pos in line_positions:
        ly = int(body_top + body_height * pos)
        draw.line(
            [(cal_left + int(size * 0.06), ly),
             (cal_right - int(size * 0.06), ly)],
            fill=gold_line,
            width=line_width
        )

    # === 마이크 (흰색, 캘린더 본문 정중앙) ===
    mic_cx = cx
    body_center_y = (header_bottom + cal_bottom) // 2
    mic_cy = body_center_y  # 본문 영역 정중앙

    # 마이크 본체 (타원) - 크게
    mic_w = int(size * 0.12)
    mic_h = int(size * 0.17)
    draw.ellipse(
        [mic_cx - mic_w, mic_cy - mic_h,
         mic_cx + mic_w, mic_cy + int(mic_h * 0.3)],
        fill=white
    )

    # U자 홀더
    holder_width = int(size * 0.01)
    holder_radius = int(size * 0.15)
    holder_cy = mic_cy + int(mic_h * 0.3)

    # U자 아크 그리기
    arc_bbox = [
        mic_cx - holder_radius, holder_cy - holder_radius + int(size * 0.02),
        mic_cx + holder_radius, holder_cy + holder_radius + int(size * 0.02)
    ]
    draw.arc(arc_bbox, start=0, end=180, fill=white, width=holder_width)

    # 스탠드 (수직선)
    stand_top = holder_cy + holder_radius + int(size * 0.02)
    stand_bottom = stand_top + int(size * 0.05)
    stand_w = int(size * 0.007)
    draw.rectangle(
        [mic_cx - stand_w, stand_top, mic_cx + stand_w, stand_bottom],
        fill=white
    )

    # 받침대 (수평선)
    base_w = int(size * 0.06)
    base_h = int(size * 0.007)
    draw.rounded_rectangle(
        [mic_cx - base_w, stand_bottom,
         mic_cx + base_w, stand_bottom + base_h],
        radius=base_h,
        fill=white
    )

    # === 음파 (마이크 양쪽) ===
    wave_cy = mic_cy - int(size * 0.02)

    for side in [-1, 1]:
        # 안쪽 음파
        wave_r1 = int(size * 0.18)
        arc1_bbox = [
            mic_cx - wave_r1, wave_cy - wave_r1,
            mic_cx + wave_r1, wave_cy + wave_r1
        ]
        if side == -1:
            draw.arc(arc1_bbox, start=150, end=210, fill=gold, width=int(size * 0.009))
        else:
            draw.arc(arc1_bbox, start=-30, end=30, fill=gold, width=int(size * 0.009))

        # 바깥쪽 음파
        wave_r2 = int(size * 0.22)
        arc2_bbox = [
            mic_cx - wave_r2, wave_cy - wave_r2,
            mic_cx + wave_r2, wave_cy + wave_r2
        ]
        if side == -1:
            draw.arc(arc2_bbox, start=155, end=205, fill=gold, width=int(size * 0.007))
        else:
            draw.arc(arc2_bbox, start=-25, end=25, fill=gold, width=int(size * 0.007))

    # 알파 채널 제거 (App Store 요구사항)
    final = Image.new('RGB', (size, size), deep_navy)
    final.paste(img, mask=img.split()[3])
    return final

def save_icon_set(base_icon, output_dir):
    sizes = [
        (1024, "icon_1024.png"),
        (180, "icon_60@3x.png"),
        (120, "icon_60@2x.png"),
        (167, "icon_83.5@2x.png"),
        (152, "icon_76@2x.png"),
        (76, "icon_76.png"),
        (40, "icon_40.png"),
        (80, "icon_40@2x.png"),
        (120, "icon_40@3x.png"),
        (58, "icon_29@2x.png"),
        (87, "icon_29@3x.png"),
        (20, "icon_20.png"),
        (40, "icon_20@2x.png"),
        (60, "icon_20@3x.png"),
    ]

    os.makedirs(output_dir, exist_ok=True)

    for size, filename in sizes:
        resized = base_icon.resize((size, size), Image.LANCZOS)
        filepath = os.path.join(output_dir, filename)
        resized.save(filepath, 'PNG')
        print(f"  ✓ {filename}")

    return sizes

def create_contents_json(sizes, output_dir):
    contents = {
        "images": [
            {"size": "20x20", "idiom": "iphone", "filename": "icon_20@2x.png", "scale": "2x"},
            {"size": "20x20", "idiom": "iphone", "filename": "icon_20@3x.png", "scale": "3x"},
            {"size": "29x29", "idiom": "iphone", "filename": "icon_29@2x.png", "scale": "2x"},
            {"size": "29x29", "idiom": "iphone", "filename": "icon_29@3x.png", "scale": "3x"},
            {"size": "40x40", "idiom": "iphone", "filename": "icon_40@2x.png", "scale": "2x"},
            {"size": "40x40", "idiom": "iphone", "filename": "icon_40@3x.png", "scale": "3x"},
            {"size": "60x60", "idiom": "iphone", "filename": "icon_60@2x.png", "scale": "2x"},
            {"size": "60x60", "idiom": "iphone", "filename": "icon_60@3x.png", "scale": "3x"},
            {"size": "20x20", "idiom": "ipad", "filename": "icon_20.png", "scale": "1x"},
            {"size": "20x20", "idiom": "ipad", "filename": "icon_20@2x.png", "scale": "2x"},
            {"size": "29x29", "idiom": "ipad", "filename": "icon_29@2x.png", "scale": "1x"},
            {"size": "29x29", "idiom": "ipad", "filename": "icon_29@2x.png", "scale": "2x"},
            {"size": "40x40", "idiom": "ipad", "filename": "icon_40.png", "scale": "1x"},
            {"size": "40x40", "idiom": "ipad", "filename": "icon_40@2x.png", "scale": "2x"},
            {"size": "76x76", "idiom": "ipad", "filename": "icon_76.png", "scale": "1x"},
            {"size": "76x76", "idiom": "ipad", "filename": "icon_76@2x.png", "scale": "2x"},
            {"size": "83.5x83.5", "idiom": "ipad", "filename": "icon_83.5@2x.png", "scale": "2x"},
            {"size": "1024x1024", "idiom": "ios-marketing", "filename": "icon_1024.png", "scale": "1x"}
        ],
        "info": {"version": 1, "author": "xcode"}
    }

    import json
    with open(os.path.join(output_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)
    print("  ✓ Contents.json")

if __name__ == "__main__":
    print("✨ Calendar + Mic Icon 생성 중...")
    print()

    icon = create_app_icon(1024)
    output_dir = "VoiceScheduler/Assets.xcassets/AppIcon.appiconset"

    print("📁 저장 중...")
    sizes = save_icon_set(icon, output_dir)
    create_contents_json(sizes, output_dir)

    print()
    print("✅ 완료!")
