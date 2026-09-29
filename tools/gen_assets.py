#!/usr/bin/env python3
"""Generate the graphics assets of the Breeze intro.

Outputs (in build/):
  logo_charset.bin   2048 bytes  multicolour charset holding the logo tiles
  logo_screens.bin   7*1024      one 1K screen per horizontal coarse shift (0..6 chars)
  font_charset.bin   2048 bytes  2x2 scroller font (glyph g -> chars 4g..4g+3 = TL,TR,BL,BR)
  font_map.inc       64tass include: ascii -> glyph table
  preview_logo.png / preview_font.png   for eyeballing

Pixel roles of the logo (multicolour char mode, 2 screen pixels wide each):
  %00 = background ($d021)      %01 = extrusion ($d022)
  %10 = face, raster gradient ($d023)      %11 = rim light (colour RAM)
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
os.makedirs(BUILD, exist_ok=True)

# ------------------------------------------------------------------ parameters
LOGO_COLS = 34          # logo width in 8x8 chars
LOGO_ROWS = 7           # logo height in chars
SHIFTS = 7              # horizontal coarse positions (0..6)
FONT_LOGO = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_LOGO_ALT = "/System/Library/Fonts/Supplemental/Impact.ttf"
FONT_SCROLL = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

# Pepto PAL palette for previews
PAL = [(0, 0, 0), (255, 255, 255), (152, 75, 67), (121, 193, 200),
       (155, 81, 165), (104, 174, 92), (82, 66, 157), (201, 214, 132),
       (155, 103, 57), (106, 84, 0), (195, 129, 121), (99, 99, 99),
       (138, 138, 138), (163, 231, 153), (138, 123, 206), (173, 173, 173)]


def text_mask(text, fontpath, width, height, top_pad=0):
    """Render `text` as a hi-res mask exactly width x height (tight bbox, stretched)."""
    f = ImageFont.truetype(fontpath, 200)
    im = Image.new("L", (2400, 400), 0)
    ImageDraw.Draw(im).text((20, 20), text, font=f, fill=255)
    im = im.crop(im.getbbox())
    im = im.resize((width, height), Image.LANCZOS)
    return np.array(im) > 110


def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = a[ys, xs]
    return out


def build_logo():
    mcw, h = LOGO_COLS * 4, LOGO_ROWS * 8          # 136 x 56 multicolour pixels
    # text is rendered at screen-pixel width (2x mc) then folded to mc pixels
    depth = 3
    face_w, face_h = mcw - depth - 2, h - depth - 8
    m = text_mask("BREEZE", FONT_LOGO, face_w * 2, face_h)
    m = m.reshape(face_h, face_w, 2).mean(axis=2) >= 0.5
    face = np.zeros((h, mcw), bool)
    face[4:4 + face_h, 1:1 + face_w] = m
    # extrusion towards bottom-right
    ext = np.zeros_like(face)
    for d in range(1, depth + 1):
        ext |= shift(face, d, d)
    ext &= ~face
    # rim light: face pixels with empty pixel above or left
    rim = face & (~shift(face, 0, 1) | ~shift(face, 1, 0))
    img = np.zeros((h, mcw), np.uint8)
    img[ext] = 1
    img[face] = 2
    img[rim] = 3
    return img


def tiles_from_img(img):
    h, w = img.shape
    rows = []
    tiles = {}
    order = [bytes(8)]           # tile 0 is always blank
    tiles[bytes(8)] = 0
    for ty in range(h // 8):
        row = []
        for tx in range(w // 4):
            blk = img[ty * 8:(ty + 1) * 8, tx * 4:(tx + 1) * 4]
            data = bytes(((int(r[0]) << 6) | (int(r[1]) << 4) | (int(r[2]) << 2) | int(r[3])) for r in blk)
            if data not in tiles:
                tiles[data] = len(order)
                order.append(data)
            row.append(tiles[data])
        rows.append(row)
    return order, rows


def preview_logo(img, path):
    # face gradient like the raster split would draw it (white -> cyan -> blue)
    grad = [1, 1, 3, 3, 3, 14, 14, 14, 6, 6]
    h, w = img.shape
    out = Image.new("RGB", (w * 2, h))
    px = out.load()
    for y in range(h):
        gc = grad[min(len(grad) - 1, max(0, (y - 4) * len(grad) // 44))]
        cols = [PAL[0], PAL[6] if False else (30, 30, 110), PAL[gc], PAL[1]]
        for x in range(w):
            c = cols[img[y, x]]
            px[2 * x, y] = c
            px[2 * x + 1, y] = c
    out = out.resize((w * 4, h * 2), Image.NEAREST)
    out.save(path)


# ------------------------------------------------------------------- scroller font
CHARS = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!?-:'()+/*&#@=<>%$"[:64]


def glyph_bits(ch, f):
    im = Image.new("L", (48, 48), 0)
    d = ImageDraw.Draw(im)
    d.text((8, 4), ch, font=f, fill=255)
    return im


def build_font():
    f = ImageFont.truetype(FONT_SCROLL, 21)
    # reference metrics from a capital letter
    ref = Image.new("L", (64, 64), 0)
    ImageDraw.Draw(ref).text((8, 4), "H", font=f, fill=255)
    bb = ref.getbbox()
    cap_top, cap_bot = bb[1], bb[3]
    glyphs = []
    for ch in CHARS:
        g = np.zeros((16, 16), bool)
        if ch != " ":
            im = Image.new("L", (64, 64), 0)
            ImageDraw.Draw(im).text((8, 4), ch, font=f, fill=255)
            bbx = im.getbbox()
            if bbx:
                x0, x1 = bbx[0], bbx[2]
                w = x1 - x0
                # centre horizontally in the 16 px cell; baseline shared by all glyphs
                dx = 8 - (w // 2) - 0
                crop = np.array(im.crop((x0, cap_top - 1, x1, cap_top - 1 + 18))) > 118
                # place: cap height rows start at y=1
                for yy in range(min(16, crop.shape[0] - 1)):
                    for xx in range(crop.shape[1]):
                        px = xx + (16 - w) // 2
                        if 0 <= px < 16 and crop[yy + 1, xx]:
                            g[yy, px] = True
        glyphs.append(g)
    return glyphs


def font_charset(glyphs):
    data = bytearray(2048)
    for gi, g in enumerate(glyphs):
        for part, (oy, ox) in enumerate([(0, 0), (0, 8), (8, 0), (8, 8)]):
            code = gi * 4 + part
            for r in range(8):
                v = 0
                for b in range(8):
                    v = (v << 1) | int(g[oy + r, ox + b])
                data[code * 8 + r] = v
    return bytes(data)


def preview_font(glyphs, path):
    cols = 16
    rows = (len(glyphs) + cols - 1) // cols
    im = Image.new("RGB", (cols * 20, rows * 20), (0, 0, 60))
    px = im.load()
    for i, g in enumerate(glyphs):
        ox, oy = (i % cols) * 20 + 2, (i // cols) * 20 + 2
        for y in range(16):
            for x in range(16):
                if g[y, x]:
                    px[ox + x, oy + y] = (255, 255, 255)
    im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(path)


# ------------------------------------------------------------------ sprite text
SPRITE_TEXT = "MUSIC: CARLOS/BREEZE    "      # 24 chars = 8 sprites x 3 chars; 20 visible ones fit the 320 px window
FONT_SPR = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"


def build_sprites():
    import font8x8
    assert len(SPRITE_TEXT) == 24
    glyphs = [np.array(font8x8.glyph(ch)) for ch in SPRITE_TEXT]
    data = bytearray()
    for spr in range(8):
        blk = bytearray(64)
        for r in range(8):
            for part in range(3):
                g = glyphs[spr * 3 + part]
                v = 0
                for b in range(8):
                    v = (v << 1) | int(g[r, b])
                blk[r * 3 + part] = v
        data += blk
    return bytes(data), glyphs


def main():
    sprdata, sprglyphs = build_sprites()
    open(os.path.join(BUILD, "sprites.bin"), "wb").write(sprdata)
    im = Image.new("RGB", (24 * 9, 10), (0, 0, 60))
    px = im.load()
    for i, g in enumerate(sprglyphs):
        for y in range(8):
            for x in range(8):
                if g[y, x]: px[i * 9 + x, 1 + y] = (255, 255, 255)
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(os.path.join(BUILD, "preview_sprites.png"))
    img = build_logo()
    tiles, rows = tiles_from_img(img)
    print(f"logo: {len(tiles)} unique tiles (max 256)")
    if len(tiles) > 256:
        sys.exit("too many tiles")
    cs = b"".join(tiles).ljust(2048, b"\0")
    open(os.path.join(BUILD, "logo_charset.bin"), "wb").write(cs)
    screens = bytearray()
    for k in range(SHIFTS):
        scr = bytearray(1024)
        for r, row in enumerate(rows):
            line = [0] * k + row + [0] * (40 - LOGO_COLS - k)
            scr[r * 40:(r + 1) * 40] = bytes(line)
        screens += scr
    open(os.path.join(BUILD, "logo_screens.bin"), "wb").write(bytes(screens))
    preview_logo(img, os.path.join(BUILD, "preview_logo.png"))

    glyphs = build_font()
    open(os.path.join(BUILD, "font_charset.bin"), "wb").write(font_charset(glyphs))
    preview_font(glyphs, os.path.join(BUILD, "preview_font.png"))
    # ascii -> glyph index map (lower case folds to upper)
    lut = [0] * 256
    for i, ch in enumerate(CHARS):
        lut[ord(ch)] = i
        lut[ord(ch.lower())] = i
    with open(os.path.join(BUILD, "font_map.inc"), "w") as f:
        f.write("font_map\n")
        for i in range(0, 256, 16):
            f.write("    .byte " + ",".join(str(x) for x in lut[i:i + 16]) + "\n")


if __name__ == "__main__":
    main()
