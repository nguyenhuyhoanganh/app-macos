#!/usr/bin/env python3
"""Sinh Resources/AppIcon.svg — icon Lumina theo phong cách icon Apple (macOS 26/27).

- Khung: 824×824 giữa canvas 1024, cạnh thẳng + góc bo liên tục (cung siêu elip) như icon Apple.
- Ký hiệu: mặt trời 8 tia trong một vòng tròn, lõi ◐ (nửa sáng nửa tối = độ sáng/tương phản màn hình), đối xứng 4 hướng,
  nằm trong vòng tròn trung tâm của lưới icon Apple nên lề trên/dưới/trái/phải bằng nhau.
- Lớp kính: viền phản quang, ánh sáng phủ mặt trên, bóng mềm dưới ký hiệu.
Chỉ dùng path/hình + gradient + opacity + transform để CoreSVG (AppKit) vẽ đúng.
"""
import math, pathlib

C, A = 512.0, 412.0                  # tâm, nửa cạnh khung (thân 824×824)
CORNER, CORNER_N = 280.0, 3.0        # góc bo liên tục: cung siêu elip bán kính 280, mũ 3
                                     # (độ sâu ≈ góc bo tròn 185 của lưới Apple, nhưng độ cong không gãy)

def squircle(cx=C, cy=C, a=A, rq=CORNER, n=CORNER_N, steps=90):
    """Cạnh thẳng + 4 góc là cung siêu elip — kiểu 'continuous corners' của icon Apple."""
    pts = []
    corners = [(+1, -1, -90, 0), (+1, +1, 0, 90), (-1, +1, 90, 180), (-1, -1, 180, 270)]  # TR, BR, BL, TL
    for sx, sy, t0, t1 in corners:
        ox, oy = cx + sx * (a - rq), cy + sy * (a - rq)        # tâm cung
        for i in range(steps + 1):
            t = math.radians(t0 + (t1 - t0) * i / steps)
            c, s = math.cos(t), math.sin(t)
            x = ox + rq * math.copysign(abs(c) ** (2 / n), c)
            y = oy + rq * math.copysign(abs(s) ** (2 / n), s)
            pts.append(f"{x:.2f} {y:.2f}")
    return "M" + " L".join(pts) + " Z"

body = squircle()
inner_rim = squircle(a=A - 1.5)

# Ký hiệu: lõi r=128, tia viên thuốc dài 86 × rộng 46, từ bán kính 190 tới 276 → đường kính ký hiệu 552
CORE_R = 112
RAY_IN, RAY_LEN, RAY_W = 168, 76, 40
RING_R, RING_W = 300, 20          # vòng tròn bao quanh mặt trời (mép trong cách đầu tia 46, cách mép thân ~102)
rays = []
for k in range(8):
    ang = k * 45
    rays.append(
        f'<rect x="{C - RAY_W/2:.1f}" y="{C - RAY_IN - RAY_LEN:.1f}" width="{RAY_W}" height="{RAY_LEN}" '
        f'rx="{RAY_W/2}" transform="rotate({ang} {C:.0f} {C:.0f})"/>'
    )
rays = "\n        ".join(rays)

# Lõi ◐: nửa trái đặc trắng, nửa phải kính mờ, viền trắng
r = CORE_R
half_left = f"M{C} {C - r} A{r} {r} 0 0 0 {C} {C + r} Z"

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Lumina app icon (sinh bởi scripts/make-icon-svg.py — sửa script, đừng sửa tay).
       Khung góc bo liên tục; mặt trời 8 tia, lõi ◐; đối xứng 4 hướng theo lưới icon Apple. -->
  <defs>
    <linearGradient id="bg" x1="300" y1="100" x2="724" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#6FD0FF"/>
      <stop offset="0.5" stop-color="#2B8CFF"/>
      <stop offset="1" stop-color="#1747D6"/>
    </linearGradient>
    <radialGradient id="bloom" cx="512" cy="512" r="420" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#E3F4FF" stop-opacity="0.50"/>
      <stop offset="0.55" stop-color="#BFE4FF" stop-opacity="0.12"/>
      <stop offset="1" stop-color="#BFE4FF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="sheen" x1="0" y1="100" x2="0" y2="560" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.34"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="rim" x1="200" y1="100" x2="824" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.85"/>
      <stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0.10"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.40"/>
    </linearGradient>
    <linearGradient id="glyph" x1="0" y1="238" x2="0" y2="786" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E4EFFF"/>
    </linearGradient>
    <radialGradient id="glyphShadow" cx="512" cy="540" r="300" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#0B2A8A" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#0B2A8A" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="drop" cx="512" cy="528" r="440" gradientUnits="userSpaceOnUse">
      <stop offset="0.88" stop-color="#000000" stop-opacity="0.18"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="body"><path d="{body}"/></clipPath>
  </defs>

  <!-- bóng đổ của thân icon -->
  <circle cx="512" cy="528" r="440" fill="url(#drop)"/>

  <g clip-path="url(#body)">
    <rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
    <rect x="100" y="100" width="824" height="824" fill="url(#bloom)"/>

    <!-- bóng mềm dưới ký hiệu -->
    <circle cx="512" cy="540" r="300" fill="url(#glyphShadow)"/>

    <!-- đĩa kính mờ bên trong vòng -->
    <circle cx="512" cy="512" r="{RING_R}" fill="#FFFFFF" fill-opacity="0.12"/>

    <!-- tia -->
    <g fill="url(#glyph)">
        {rays}
    </g>

    <!-- lõi ◐ -->
    <circle cx="512" cy="512" r="{r}" fill="#FFFFFF" fill-opacity="0.34"/>
    <path d="{half_left}" fill="url(#glyph)"/>
    <circle cx="512" cy="512" r="{r - 10}" fill="none" stroke="#FFFFFF" stroke-width="20"/>

    <!-- vòng tròn bao quanh mặt trời -->
    <circle cx="512" cy="512" r="{RING_R}" fill="none" stroke="url(#glyph)" stroke-width="{RING_W}"/>

    <!-- ánh sáng phủ mặt trên như mặt kính -->
    <rect x="100" y="100" width="824" height="460" fill="url(#sheen)"/>
  </g>

  <!-- viền phản quang -->
  <path d="{inner_rim}" fill="none" stroke="url(#rim)" stroke-width="3"/>
</svg>
'''
out = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "AppIcon.svg"
out.write_text(svg)
print(f"svg → {out}")
