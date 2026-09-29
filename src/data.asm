; ============================================================================
;  data tables
; ============================================================================

; ---------------------------------------------------------------------------
;  signed sine tables, one 256 byte page per amplitude level 0..AMP_LEVELS-1
;  amptab + L*256 + phase  =  round(L * sin(phase * 2pi / 256))
; ---------------------------------------------------------------------------
AMP_LEVELS  = 17
* = WAVET
; wave samples for the logo, pre-sampled with a stride of 8 phase steps
;   wavet + (level*8 + r)*64 + m  =  8 + round(level * sin((r + 8*(m mod 32)) * 2pi/256))
wavet
        .for lvl = 0, lvl < 7, lvl += 1
        .for r = 0, r < 8, r += 1
        .for m = 0, m < 64, m += 1
        .byte 8 + int(round(lvl * sin((r + 8 * (m % 32)) * 2 * pi / 256)))
        .next
        .next
        .next

* = AMPTAB
amptab
        .for l = 0, l < AMP_LEVELS, l += 1
        .for i = 0, i < 256, i += 1
        .byte int(round(l * sin(i * 2 * pi / 256))) & $ff
        .next
        .next

; ---------------------------------------------------------------------------
;  small tables in the main code bank
; ---------------------------------------------------------------------------
* = DATA_BANK
        .align 256
; $d016 value for  index = fine + 32 :  clamps the fine scroll to 0..7
clamp
        .for i = 0, i < 256, i += 1
        .if i < 32
        .byte $18
        .elsif i < 40
        .byte $18 + (i - 32)
        .elsif i < 128
        .byte $18 + 7
        .else
        .byte $18
        .fi
        .next

; low bytes of 64*k
lo64    .byte 0, 64, 128, 192

; the FLD pattern of $d011 values (see intro.asm), also used to restore dtab
dtabpat
        .for i = 0, i < 256, i += 1
        .if i < 203
        .byte $18 | ((i + 1) & 7)
        .else
        .byte $10 | ((i + 1) & 7)
        .fi
        .next

; y positions of the credit sprites: 6 + 3 sin
sprsin
        .for i = 0, i < 256, i += 1
        .byte 6 + int(round(3 * sin(i * 2 * pi / 256)))
        .next

; unsigned bar position (0..96), used for the copper bars
barsin
        .for i = 0, i < 256, i += 1
        .byte round(48 + 47 * sin(i * 2 * pi / 256))
        .next

; ---------------------------------------------------------------------------
;  fading.  darker[c] is the colour one step darker; fadetab[level*16+c]
;  is colour c faded to level 0..5 (5 = untouched)
; ---------------------------------------------------------------------------
darker  = [0, 15, 9, 14, 6, 11, 0, 8, 9, 0, 2, 0, 11, 5, 6, 12]
fadetab
        .for lvl = 0, lvl < 6, lvl += 1
        .for c = 0, c < 16, c += 1
        v := c
        .for k = 0, k < 5 - lvl, k += 1
        v := darker[v]
        .next
        .byte v
        .next
        .next

; ---------------------------------------------------------------------------
;  colours (unfaded).  Bars: ramp dark -> light, mirrored, 14 lines each
; ---------------------------------------------------------------------------
NBARS   = 6
BARLEN  = 14
barramps = [6,14,3,1, 9,2,8,7, 11,5,13,1, 6,4,10,1, 9,8,7,1, 11,12,15,1]  ; blue, copper, green, purple, gold, steel
barsrc                              ; full 14 line shapes, NBARS * BARLEN
        .for b = 0, b < NBARS, b += 1
        .for k = 0, k < 4, k += 1
        .byte barramps[b * 4 + k], barramps[b * 4 + k]
        .next
        .for k = 2, k >= 0, k -= 1
        .byte barramps[b * 4 + k], barramps[b * 4 + k]
        .next
        .next
barpal  .fill NBARS * BARLEN, 0     ; faded copy, made at run time

; dark plate behind the scroller (16 lines), and the gradient of the logo face
platesrc
        .byte 11, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 11
EXTR_COL = 11                       ; extrusion / shadow of the logo ($d022)
gradsrc                             ; 56 lines, top -> bottom  ($d023 = face): chrome
        .byte 6, 6, 6, 6                                 ; 0-3   (above the letters)
        .byte 6, 6, 14, 14, 14, 3, 3, 3, 3, 1, 1, 1      ; 4-15  dark -> white
        .byte 1, 1, 1, 3, 3, 14, 14                      ; 16-22 white horizon
        .byte 6, 6, 6, 6, 14, 14, 3, 3, 14, 14, 6, 6     ; 23-34 reflection
        .byte 6, 6, 6, 6, 14, 14, 6, 6, 6, 6, 6, 6       ; 35-46
        .byte 6, 6, 6, 6, 6, 6, 6, 6, 6                  ; 47-55

plate   .fill 16, 0                 ; faded copy (read by the scroller cells)

; colours of the scroller rows (colour RAM)
scr_col_top = 1
scr_col_bot = 3

; ---------------------------------------------------------------------------
;  scroll text  (ASCII, lower case folds to upper case).  0 = wrap around
; ---------------------------------------------------------------------------
scrolltext
        .text "        breeze proudly presents a brand new c64 intro !     "
        .text "the logo is waving, the raster bars are dancing and the music is "
        .text "by carlos of breeze ...     "
        .text "coded in pure 6510 assembly with open borders, fld, stable rasters "
        .text "and lots of cycles ...     "
        .text "greetings fly out to all the sceners on the c64, "
        .text "to everybody who still loves the breadbin and to all who "
        .text "keep this little machine alive !     "
        .text "press space to leave this screen ...        "
        .byte 0

; ascii -> glyph index (generated by tools/gen_assets.py)
        .include "../build/font_map.inc"
