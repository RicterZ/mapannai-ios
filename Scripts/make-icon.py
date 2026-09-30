#!/usr/bin/env python3
"""Generate the original map/connection icon in blue. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw
import json
root = Path(__file__).resolve().parents[1]
folder = root / 'App/Assets.xcassets/AppIcon.appiconset'
folder.mkdir(parents=True, exist_ok=True)
image = Image.new('RGB', (1024, 1024), '#399ADA')
draw = ImageDraw.Draw(image)
draw.polygon([(180,290),(395,210),(630,290),(845,210),(845,734),(630,814),(395,734),(180,814)], fill='#EFF9FF')
draw.polygon([(395,210),(630,290),(630,814),(395,734)], fill='#CAE7F9')
draw.line([(395,245),(395,700)], fill='#399ADA', width=10)
draw.line([(630,323),(630,780)], fill='#399ADA', width=10)
points = []
for i in range(101):
    t = i / 100; s = 1 - t
    points.append((int(s*s*280+2*s*t*470+t*t*741), int(s*s*620+2*s*t*240+t*t*430)))
draw.line(points, fill='#399ADA', width=30)
for x, y in [points[0], points[-1]]:
    draw.ellipse((x-47,y-47,x+47,y+47), fill='#399ADA')
    draw.ellipse((x-20,y-20,x+20,y+20), fill='#FFFFFF')
image.save(folder / 'AppIcon.png')
(folder / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
