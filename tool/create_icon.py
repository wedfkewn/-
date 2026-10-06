"""Deterministic native typography and stamp geometry; no generated glyphs."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json
import random

ROOT = Path(__file__).resolve().parents[1]
rng = random.Random(602)
size = 1024
paper = Image.new('RGB', (size, size), '#f7f3ea')
pixels = paper.load()
for y in range(size):
    for x in range(size):
        noise = rng.randrange(-3, 4)
        pixels[x, y] = (247 + noise, 243 + noise, 234 + noise)
mark = Image.new('RGBA', (size, size))
draw = ImageDraw.Draw(mark)
# The seal occupies 62% of the canvas, inside Android's adaptive safe circle.
left, right = 202, 822
points = []
for x in range(left, right + 1, 8): points.append((x, left + rng.randrange(-4, 5)))
for y in range(left, right + 1, 8): points.append((right + rng.randrange(-4, 5), y))
for x in range(right, left - 1, -8): points.append((x, right + rng.randrange(-4, 5)))
for y in range(right, left - 1, -8): points.append((left + rng.randrange(-4, 5), y))
draw.polygon(points, fill='#ad2922')
draw.rectangle((224, 224, 800, 800), outline='#f7f3ea', width=9)
font = ImageFont.truetype(str(ROOT / 'assets/fonts/MaShanZheng-Regular.ttf'), 500)
box = draw.textbbox((0, 0), '修', font=font)
draw.text(((size - (box[2] - box[0])) / 2 - box[0], (size - (box[3] - box[1])) / 2 - box[1]), '修', font=font, fill='#f7f3ea')
# Sparse ink wear remains legible at launcher sizes.
for _ in range(170):
    x, y = rng.randrange(214, 810), rng.randrange(214, 810)
    draw.ellipse((x, y, x + 2, y + 3), fill='#c2584d')
icon = Image.alpha_composite(paper.convert('RGBA'), mark).convert('RGB')
out = ROOT / 'assets/icon'
out.mkdir(parents=True, exist_ok=True)
icon.save(out / 'app-icon.png')
adaptive_mark = Image.new('RGBA', (size, size))
adaptive_mark.alpha_composite(mark.resize((736,736), Image.Resampling.LANCZOS), (144,144))
adaptive_mark.save(out / 'adaptive-foreground.png')
(out / 'README.md').write_text('朱印「修」字：MaShanZheng 字体与确定性印章几何。由 tool/create_icon.py 重建；字体许可证见 assets/SOURCES.md。\n', encoding='utf-8')
ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
data = json.loads((ios / 'Contents.json').read_text())
for entry in data['images']:
    scale = float(entry['scale'].removesuffix('x'))
    pixels = round(float(entry['size'].split('x')[0]) * scale)
    icon.resize((pixels, pixels), Image.Resampling.LANCZOS).save(ios / entry['filename'])
res = ROOT / 'android/app/src/main/res'
for density, pixels in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    folder=res/f'mipmap-{density}'
    icon.resize((pixels,pixels),Image.Resampling.LANCZOS).save(folder/'ic_launcher.png')
    adaptive=round(pixels*108/48)
    adaptive_mark.resize((adaptive,adaptive),Image.Resampling.LANCZOS).save(folder/'ic_launcher_foreground.png')
folder=res/'mipmap-anydpi-v26'
folder.mkdir(exist_ok=True)
(folder/'ic_launcher.xml').write_text('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/icon_paper"/><foreground android:drawable="@mipmap/ic_launcher_foreground"/></adaptive-icon>\n')
(res/'values/icon_colors.xml').write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="icon_paper">#f7f3ea</color></resources>\n')
print('Created iOS and Android stamp icons')
