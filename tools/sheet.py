"""Builds JPEG contact sheets (2x2, half size) from build/cap-*.png for quick review."""
import glob, sys
from PIL import Image
caps = sorted(glob.glob("build/cap-*.png"))
for s in range(0, len(caps), 4):
    sheet = Image.new("RGB", (1280, 760))
    for i, p in enumerate(caps[s:s + 4]):
        im = Image.open(p).convert("RGB").resize((640, 380))
        sheet.paste(im, ((i % 2) * 640, (i // 2) * 380))
    sheet.save(f"build/sheet{s // 4}.jpg", quality=85)
print(len(caps), "captures")
