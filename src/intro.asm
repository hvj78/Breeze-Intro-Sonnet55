; ============================================================================
;  BREEZE intro  -  Commodore 64 (PAL), 6510 assembly, assembled with 64tass
;
;  What is on the screen
;  ---------------------
;   * a big multicolour-char logo that fades in, then moves up/down (FLD), left/right
;     (pre-shifted screens + fine scroll) and finally waves (fine scroll per raster line)
;   * copper bars (border + background colour per raster line)
;   * a 2x2 character scroller with a dark plate; it bobs up/down and dips into the
;     bottom border region
;   * top and bottom border opened; a sprite credit line lives in the bottom border
;   * SID music by Carlos/Breeze (HVSC: Magic.sid, played from $1000)
;   * space -> everything fades out (picture and volume), then back to BASIC
;
;  Frame structure  (PAL: 63 cycles per raster line, 312 lines, 50 Hz)
;  ---------------------------------------------------------------
;  One raster IRQ per frame (line 42, made cycle stable with the "double IRQ" method)
;  enters the RASTER BLOCK: an unrolled, cycle exact sequence of 63-cycle "cells", one
;  cell per raster line, running from line 46 down to the end of the scroller.  Each
;  cell rewrites VIC-II registers in the invisible part of the line:
;
;    lead-in  FLD cells    $d011 keeps bad lines away -> the logo is pushed down (y move)
;    logo     7 rows x 8   $d016 (wave) + $d023 (gradient) every line, $d018 selects a
;                          pre-shifted screen for every char row (x move)
;    M0       1 cell       switches to the scroller mode (hires charset, screen 2)
;    mid      FLD cells    copper bars ($d020/$d021), bad lines suppressed
;    scroller 2 rows x 8   2x2 char scroller, "plate" colours behind it
;    cleanup  1 cell       back to black borders / multicolour mode, sprites on
;
;  A "short" cell (20 cycles) precedes every bad line: the VIC steals 43 cycles
;  (12..54) of that line from the CPU, so 20 + 43 = 63.
;
;  The mid and lead-in zones are unrolled so that the routine can be entered at a
;  computed position (jmp (zp)): the number of FLD lines differs from frame to frame
;  but every cell always takes exactly 63 cycles (a loop with a taken branch would
;  cost an extra cycle whenever it straddles a page boundary).
;
;  Between the end of the block and the next IRQ the main loop runs "update"
;  (music, timeline, tables for the next block) - see update.asm.  Its budget is
;  about 5.5K cycles per frame; tools/profile.py measures it.
;
;  IRQ chain per frame:  irq1 (42) -> irq2 (43) -> block -> [irq_bot (249)] ->
;                        irq_spr (300) -> irq1 ...
;
;  Cell timing convention:  c0 = cycle 55 of raster line L (first cycle the CPU owns
;  again after a bad line).  Colour registers that must not show in the visible part
;  of the line ($d020) are written in c6..c19 = cycles 61..11 of the next line (the
;  VICE/PAL crop shows cycles 13..60).
;
;  Memory map
;  ----------
;   $0801 basic stub     $0810 boot, init, exit       $1000 SID (Magic.sid)
;   $2000 per-line tables (bar, dtab, wave, grad ...)
;   $2300 update.asm     $3800 small tables (data.asm)
;   VIC bank 1: $4000 logo charset   $4800 scroller font    $5000 logo screens (7)
;               $6c00/$7000 scroller screens (double buffer)   $7400 credit sprites
;   $8000 irq + raster block         $ab00 wave tables       $b900 sine tables
; ============================================================================

.include "../build/config.inc"   ; DEBUG_BG, DEBUG_EDGE, DEBUG_CPU (make CFG="DEBUG_CPU=1")
WAVET       = $ab00     ; wave sample tables (3.5K)
AMPTAB      = $b900     ; signed sine tables (17 pages)
DATA_BANK   = $3800     ; small tables (page aligned, after the update code)
MAXLEAD     = 32        ; unrolled lead-in FLD cells
MAXMID      = 150       ; unrolled mid-zone FLD cells
BLOCK       = $8000

; ------------------------------------------------------------------ memory map
MUSIC_INIT  = $1000
MUSIC_PLAY  = $1003

CHR_LOGO    = $4000         ; logo charset (2K)
CHR_FONT    = $4800         ; scroller font charset (2K)
SCR_LOGO    = $5000         ; 7 logo screens, one per coarse x shift
SCR_SCROLL  = $6c00         ; scroller screen 0
SCR_SCROLL2 = $7000         ; scroller screen 1 (double buffered)
SPR_DATA    = $7400         ; sprite text (8 x 64 bytes), pointers $d0..$d7

D018_LOGO   = $40           ; screen $5000, charset $4000  (+ k*$10 per shift)
D018_SCROLL = $b2           ; screen $6c00, charset $4800 (buffer 1: $c2)

; ------------------------------------------------------------------ zero page
zp_sa       = $02
zp_sx       = $03
zp_sy       = $04
zp_flag     = $05           ; set by the IRQ when the block is done
zp_ent      = $06           ; (2) entry pointer into the unrolled lead-in cells
zp_midp     = $08           ; (2) entry pointer into the unrolled mid zone
zp_ymid     = $12           ; Y index at start of mid zone
zp_d018r0   = $0a           ; $d018 for logo row 0
zp_d018sc   = $0b           ; $d018 for scroller
zp_d016sc   = $0c           ; $d016 for scroller (fine x scroll)
zp_d016lg   = $0d           ; $d016 for lead-in (multicolour, no scroll)
zp_frame    = $14           ; frame counter (16 bit)
zp_tmp      = $16
zp_tmp2     = $17
zp_dlast    = $1b           ; $d011 value written by the last logo cell
zp_oldn     = $1c           ; previous frame: patched dtab index (logo entry)
zp_olds2    = $1d           ; previous frame: first patched dtab index (scroller)
zp_n        = $18           ; lead-in FLD cell count
zp_m        = $19           ; mid FLD cell count

; big tables (page aligned so indexed reads never cross a page)
bar         = $2000         ; colour for $d020/$d021 per line
dtab        = $2100         ; $d011 value per line
wave        = $2200         ; $d016 value per logo line (64 entries)
grad        = $2240         ; $d023 value per logo line (64 entries)
rowd018     = $2280         ; $d018 per logo row (7 entries)
dsctab      = $2290         ; $d011 per scroller cell (16 entries)

; ============================================================================
* = $0801
        .word (+), 2026
        .null $9e, format("%d", start)
+       .word 0

* = $0810
start:
        lda $02a6               ; KERNAL: 1 = PAL, 0 = NTSC
        bne ispal
        ldx #0                  ; this intro is cycle exact for PAL machines only
nt_loop lda ntscmsg,x
        beq nt_end
        jsr $ffd2
        inx
        bne nt_loop
nt_end  rts
ntscmsg .byte 13
        .text "SORRY, THIS INTRO NEEDS A PAL C64."
        .byte 13, 0
ispal   sei
        lda #$35
        sta $01                 ; RAM everywhere, I/O visible
        ldx #$ff
        txs
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #$00
        sta $d01a               ; no VIC irq for now
        sta $d015               ; no sprites
        lda #$ff
        sta $d019
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda #<irq1
        sta $fffe
        lda #>irq1
        sta $ffff

        lda $dd00               ; VIC bank 1 ($4000-$7fff)
        and #$fc
        ora #$02
        sta $dd00

        lda #$0b
        sta $d011               ; display off during setup
        lda #$00
        sta $d020
        sta $d021
        lda #$06
        sta $d022
        lda #$00
        sta $d023
        lda #$18
        sta $d016

        jsr init_all

        lda #$00
        jsr MUSIC_INIT
        lda #$30
        sta $d418               ; silent until the fade-in raises the volume
        jsr frame_logic

        lda #$2a
        sta $d012
        lda #$1b
        sta $d011
        lda #$01
        sta $d01a
        cli

main:   lda zp_flag
        beq main
        lda #0
        sta zp_flag
        jsr update
        lda zp_exit
        cmp #2
        bne main
        jmp do_exit

nmi:    rti

; ---------------------------------------------------------------- init
init_all:
        ldx #0                  ; colour RAM black
        lda #0
-       sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $db00,x
        inx
        bne -
        ldx #$43                ; clear our zero page ($02..$45)
-       sta $02,x
        dex
        bpl -
        lda #D018_LOGO
        sta zp_d018r0
        lda #D018_SCROLL
        sta zp_d018sc
        lda #$18
        sta zp_d016lg
        lda #$08
        sta zp_d016sc
        lda #<scrolltext
        sta zp_sp
        lda #>scrolltext
        sta zp_sp+1
        ldx #NBARS-1            ; spread the copper bar phases
-       txa
        asl
        asl
        asl
        asl
        sta zp_bph,x
        txa
        asl
        asl
        adc zp_bph,x
        sta zp_bph,x
        dex
        bpl -
        ldx #0                  ; dtab = FLD pattern
-       lda dtabpat,x
        sta dtab,x
        inx
        bne -
        ldx #6                  ; all logo rows start with shift 0
        lda #D018_LOGO
-       sta rowd018,x
        dex
        bpl -
        ldx #63                 ; flat wave
        lda #$1b
-       sta wave,x
        dex
        bpl -
        ldx #7                  ; credit text sprites (shown in the open bottom border)
-       txa
        clc
        adc #$d0                ; pointer = SPR_DATA/64 + k
        sta SCR_SCROLL+1016,x
        sta SCR_SCROLL2+1016,x
        txa
        asl
        tay
        lda sprx,x
        sta $d000,y
        lda #6                  ; y = 6  ->  raster line 262 (the wrap-around trick)
        sta $d001,y
        dex
        bpl -
        lda #$ff
        sta $d017               ; expand y
        sta $d01d               ; expand x
        lda #0
        sta $d01c
        sta $d01b
        sta $d015
        lda #$60                ; x >= 256 for sprites 5 and 6
        sta $d010
        lda #0                  ; everything black at fade level 0: run all jobs once
        sta zp_fade
        sta zp_fbase
        sta zp_ftask
        ldx #NFT/2
-       txa
        pha
        jsr do_fade_tasks
        pla
        tax
        dex
        bne -
        rts

sprx    .byte 24, 72, 120, 168, 216, 8, 56, 0      ; sprites 5,6 have x bit 8 set (264, 312)

; ---------------------------------------------------------------- leave
do_exit:
        sei
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        ldx #$18                ; silence
        lda #0
-       sta $d400,x
        dex
        bpl -
        lda #$37                ; ROMs back, VIC bank 0, standard screen mode
        sta $01
        lda $dd00
        ora #$03
        sta $dd00
        lda #$1b
        sta $d011
        lda #$c8
        sta $d016
        lda #$14
        sta $d018
        lda #$0e
        sta $d020
        lda #$06
        sta $d021
        jmp $fce2               ; KERNAL cold start -> BASIC

; ============================================================================
;  cell macros
; ============================================================================
filler  .macro
        .if \1 < 0
        .error "negative filler"
        .fi
        .if \1 & 1
        bit $ea                 ; 3
        .rept (\1 - 3) / 2
        nop
        .next
        .else
        .rept \1 / 2
        nop
        .next
        .fi
        .endm

; optional calibration stripe on $d021 (visible!): exactly 30 cycles
dbgedge .macro
        .if DEBUG_EDGE
        #filler 12
        lda #1                  ; +12
        sta $d021               ; +14  write +17
        nop
        nop
        nop
        lda #0
        sta $d021               ; write +29
        .else
        #filler 30
        .fi
        .endm

; --- FLD / bar cell (63 cycles) -------------------------------------------------
;  in : X = bar[y]   A = dtab[y]   Y = y        out: same for y+1
fldcell .macro
        nop                     ; c0
        stx $d021               ; c2   write c5   (bg: hidden behind the right border)
        stx $d020               ; c6   write c9   (border: cycle 1 = invisible)
        sta $d011               ; c10  write c13
        #dbgedge                ; c14 .. c43   (a plain 30 cycle delay unless DEBUG_EDGE)
        #filler 9               ; c44
        iny                     ; c53
        ldx bar,y               ; c55
        lda dtab,y              ; c59
        .endm

; --- logo cells ------------------------------------------------------------------
;  in : A = grad[k]  X = wave[k]  Y = k         out: k+1
logo_short .macro
        ; logo_short
        nop                     ; c0
        sta $d023               ; c2   write c5
        stx $d016               ; c6   write c9
        iny                     ; c10
        lda grad,y              ; c12
        ldx wave,y              ; c16
        ; logo_short 20
        .endm

;  \1 = 1: also write $d018 for the next row from rowd018+\2
logo_norm .macro
        ; logo_norm
        nop                     ; c0
        sta $d023               ; c2
        stx $d016               ; c6
        iny                     ; c10
        #dbgedge                ; c12 .. c41
        .if \1
        lda rowd018+\2          ; c42
        sta $d018               ; c46
        #filler 5               ; c50
        .else
        #filler 13              ; c42
        .fi
        lda grad,y              ; c55
        ldx wave,y              ; c59
        ; logo_norm 63
        .endm

; last logo cell: prepares the mid zone (falls through into M0)
logo_last .macro
        nop                     ; c0
        sta $d023               ; c2
        stx $d016               ; c6
        lda zp_dlast            ; c10   (A is reloaded below)
        sta $d011               ; c13   write c16
        #filler 35              ; c17
        ldy zp_ymid             ; c52
        ldx bar,y               ; c55
        lda dtab,y              ; c59
        .endm

; --- scroller cells ------------------------------------------------------------------
;  cell k (0..15) writes the colour of scroller line k (plate[k]) and, in the normal
;  cells, the constant $d011 value from dsctab[k].  X = plate[k] on entry.
;  \1 = k
scr_short .macro
        nop                     ; c0
        stx $d021               ; c2
        stx $d020               ; c6
        ldx plate+\1+1          ; c10
        nop                     ; c14
        nop                     ; c16
        nop                     ; c18
        .endm

scr_norm .macro
        nop                     ; c0
        stx $d021               ; c2
        stx $d020               ; c6
        lda dsctab+\1           ; c10
        sta $d011               ; c14  write c17
        .if \1 < 15
        #filler 41              ; c18
        ldx plate+\1+1          ; c59
        .else
        #filler 45              ; c18
        .fi
        .endm

* = $2300
        .include "update.asm"
        .include "data.asm"

; ============================================================================
;  raster interrupts + THE BLOCK
; ============================================================================
* = BLOCK

; ---------------------------------------------------------------------------
;  "Double IRQ" stabiliser.
;  irq1 fires at raster line 42 with 0..7 cycles of jitter (the interrupted
;  instruction has to finish).  It points the vector to irq2, asks for an
;  interrupt in the next line, re-enables interrupts and runs a slide of NOPs.
;  irq2 arrives during one of those 2-cycle NOPs, so its jitter is only 0 or 1
;  cycle.  The lda/cmp $d012 pair below reads the raster register twice: the
;  branch is taken (3 cycles) or not (2 cycles) depending on that last cycle of
;  jitter, which makes both paths meet at the same absolute cycle.
;  The delay before the lda/cmp pair (STAB_DELAY/STAB_NOPS/STAB_BIT) is NOT the
;  textbook value: with the theoretical delay the result was still off by one cycle
;  from frame to frame (measured with a calibration stripe, 8 pixels = 1 cycle).
;  tools/tune_stab.py tried all 18 combinations; only this one was jitter free in
;  every sample.  The delay loop after the "+" label (ENTRY_*) then lands the first
;  instruction of the first cell on cycle 55 of line 46 (monitor shows "46 / 55").
;  If you change anything in front of the stabiliser, re-run the tuner.
; ---------------------------------------------------------------------------
irq1:
        sta zp_sa
        stx zp_sx
        sty zp_sy
        lda #<irq2
        sta $fffe
        lda #>irq2
        sta $ffff
        inc $d012               ; next line
        lda #$ff
        sta $d019
        tsx
        cli
        .rept 16
        nop
        .next
        brk                     ; never reached

irq2:
        txs                     ; drop the irq2 frame, back to the irq1 frame
        ldx #STAB_DELAY
-       dex
        bne -
        .rept STAB_NOPS
        nop
        .next
        .if STAB_BIT
        bit $ea
        .fi
        lda $d012
        cmp $d012
        beq +
+       ; ---- from here on the CPU runs at a fixed cycle of line 44 --------
        ldx #ENTRY_PAD          ; 2
-       dex                     ; 5n-1
        bne -
        .rept ENTRY_NOPS
        nop
        .next
        .if ENTRY_BIT
        bit $ea
        .fi
        ldy #0                  ; y = line index (0 = raster line 46)
        ldx bar                 ; x = colour for the first cell
        lda dtab                ; a = $d011 value for the first cell
        jmp (zp_ent)            ; enter the unrolled lead-in at the computed cell

        .align 256
block:
        ; ------------------------------------------------------------ lead-in
lead_start:
        .for i = 0, i < MAXLEAD, i += 1
        #fldcell
        .next
lead_end:

        ; T1: last FLD cell, black background, prepares the logo start
        nop                     ; c0
        ldx #0                  ; c2
        .if DEBUG_BG
        ldy #$0b                ; c4
        sty $d021               ; c6   write c9
        .else
        stx $d021               ; c4   write c7
        nop                     ; c8
        .fi
        stx $d020               ; c10  write c13
        sta $d011               ; c14  write c17
        lda zp_d018r0           ; c18
        sta $d018               ; c21
        lda zp_d016lg           ; c25
        sta $d016               ; c28
        ldy #0                  ; c32
        #filler 21              ; c34
        lda grad                ; c55
        ldx wave                ; c59

        ; ------------------------------------------------------------ logo
        .for g = 0, g < 7, g += 1
        #logo_short
        .for i = 0, i < 7, i += 1
        .if g == 6 && i == 6
        #logo_last
        .elsif g < 6 && i == 2
        #logo_norm 1, g+1
        .else
        #logo_norm 0, 0
        .fi
        .next
        .next

        ; ------------------------------------------------------------ M0
        ; first mid cell (raster S+55): switches to the scroller mode inside the
        ; invisible part of the line, no bars (black stays for one more line)
        nop                     ; c0
        ldx zp_d016sc           ; c2
        stx $d016               ; c5   write c8   (cycle 0: hires for the FLD lines)
        sta $d011               ; c9   write c12
        ldx zp_d018sc           ; c13
        stx $d018               ; c16  write c19
        #filler 28              ; c20
        iny                     ; c48
        ldx bar,y               ; c50
        lda dtab,y              ; c54
        jmp (zp_midp)           ; c58
        ; ------------------------------------------------------------ mid FLD zone
mid_start:
        .for i = 0, i < MAXMID, i += 1
        #fldcell
        .next
mid_end:

        ; ------------------------------------------------------------ scroller
        .for k = 0, k < 16, k += 1
        .if k == 0 || k == 8
        #scr_short k
        .else
        #scr_norm k
        .fi
        .next

        ; ------------------------------------------------------------ cleanup cell
        ; (raster line S2+15, cycle 55: the last scroller line is done)
        lda #0                  ; c0    black borders again
        sta $d021               ; c2    write c5
        sta $d020               ; c6    write c9
        ldx #$18                ; c10   multicolour text mode for the next logo
        stx $d016               ; c12   write c15
        lda #$7f                ; c16   the credit sprites may appear now (raster line 262)
        sta $d015
        lda #<irq_bot           ; c18   -- from here on nothing is critical
        sta $fffe
        lda #>irq_bot
        sta $ffff
        lda $d011               ; current raster line >= 248 ?
        bmi late
        lda $d012
        cmp #248
        bcs late
        lda #249                ; not yet: open the bottom border from a small irq
        sta $d012
        jmp fin
late:   lda #$10                ; already there (or past): RSEL=0 right now, the compare
        jsr next_spr            ;  line of the next irq is 300 (sprites off)
fin:    lda #$ff
        sta $d019
        lda #1
        sta zp_flag
        ldy zp_sy
        ldx zp_sx
        lda zp_sa
        rti

; next irq = irq_spr at raster line 300 ($12c): A = $d011 value to write (bit 7 is added)
next_spr:
        ora #$80
        sta $d011
        lda #<irq_spr
        sta $fffe
        lda #>irq_spr
        sta $ffff
        lda #44
        sta $d012
        rts

; small irq at raster line 249: opens the bottom border (RSEL=0 after line 247,
; before line 251), then hands over to irq1 for the next frame
irq_bot:
        pha
        lda #$10
        jsr next_spr            ; RSEL=0 now; next irq at line 300
        lda #$ff
        sta $d019
        pla
        rti

; irq at raster line 300: the credit sprites have been drawn, switch them off (this also
; hides their wrap-around twin at raster line 6) and hand over to irq1 for the next frame
irq_spr:
        pha
        lda #0
        sta $d015
        lda #$10                ; compare line 42 needs bit 7 = 0
        sta $d011
        lda #<irq1
        sta $fffe
        lda #>irq1
        sta $ffff
        lda #$2a
        sta $d012
        lda #$ff
        sta $d019
        pla
        rti

LEAD_SZ = (lead_end - lead_start) / MAXLEAD
MID_SZ  = (mid_end - mid_start) / MAXMID

; entry pointer tables: n cells before the end of each zone
leadp_lo
        .for i = 0, i <= MAXLEAD, i += 1
        .byte <(lead_end - i * LEAD_SZ)
        .next
leadp_hi
        .for i = 0, i <= MAXLEAD, i += 1
        .byte >(lead_end - i * LEAD_SZ)
        .next
midp_lo
        .for i = 0, i <= MAXMID, i += 1
        .byte <(mid_end - i * MID_SZ)
        .next
midp_hi
        .for i = 0, i <= MAXMID, i += 1
        .byte >(mid_end - i * MID_SZ)
        .next

; ============================================================================
;  data
; ============================================================================
* = $2000
        .fill 256, 0            ; bar
        .fill 256, 0            ; dtab
        ; wave: static test sine (fine scroll 0..7 + $18)
        .for i = 0, i < 64, i += 1
        .byte $18 + int(3.5 + 3.5 * sin(i * 3.14159265 / 16))
        .next
        ; grad: white -> cyan -> light blue -> blue
        .for i = 0, i < 64, i += 1
        .byte [1, 1, 1, 1, 1, 1, 1, 1, 3, 3, 3, 3, 3, 3, 3, 3, 14, 14, 14, 14, 14, 14, 14, 14, 6, 6, 6, 6, 6, 6, 6, 6, 14, 14, 14, 14, 14, 14, 14, 14, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0][i]
        .next
        .fill 64, 0             ; rowd018 (filled at runtime)

* = $1000
        .binary "../music/magic.bin"

* = CHR_LOGO
        .binary "../build/logo_charset.bin"
* = CHR_FONT
        .binary "../build/font_charset.bin"
* = SCR_LOGO
        .binary "../build/logo_screens.bin"
* = SCR_SCROLL
        .fill 1024, 0
* = SCR_SCROLL2
        .fill 1024, 0
* = SPR_DATA
        .binary "../build/sprites.bin"
* = $7fff
        .byte 0
