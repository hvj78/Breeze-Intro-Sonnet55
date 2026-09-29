; ============================================================================
;  per frame work.  Runs in the main loop after the raster block finished
;  (raster lines ~250..311 and 0..42), so it may take at most ~5.5K cycles.
;
;  frame phase (frame & 3):   0,2: copper bars are repainted
;                             3  : the scroller shifts one character
;                             1  : (free)                  fade jobs run any time
; ============================================================================

; ------------------------------------------------------------------ timeline
;  all values in frames (50 per second)
T_FADEIN        = 25        ; logo starts to fade in
FADE_IN_SPEED   = 12        ; frames per fade step (6 levels)
FADE_OUT_SPEED  = 8
T_SCROLL        = 51        ; scroller starts (must be = 3 mod 4)
T_BARS          = 120       ; first copper bar appears, one more every BAR_SPEED
BAR_SPEED       = 25
T_YMOVE         = 160       ; logo starts to move up/down
T_XMOVE         = 460       ; ... and left/right
T_WAVE          = 760       ; ... and waves
T_BOB           = 1060      ; scroller starts to bob up/down
AY_MAX          = 12        ; amplitude in pixels / wave level
AX_MAX          = 16
AW_MAX          = 6
AB_MAX          = 12
SPD_Y           = 2         ; phase speeds (256 = one period)
SPD_X           = 3
SPD_W           = 5
SPD_B           = 3
S_CENTER        = 65        ; raster line where the logo starts (centre)
G_CENTER        = 27        ; logo x offset in pixels (centre), 0..55
S2_CENTER       = 227       ; raster line where the scroller starts (centre); the second
                            ; char row needs a bad line, so S2 + 8 <= 247 -> S2 <= 239
BAR_TOP         = 82        ; bar table index of the highest bar position
SCROLL_SPEED    = 2         ; pixels per frame (divides 8)

; ------------------------------------------------------------ more zero page
zp_ay       = $20           ; amplitudes
zp_ax       = $21
zp_aw       = $22
zp_ab       = $23
zp_py       = $24           ; sine phases
zp_px       = $25
zp_pw       = $26
zp_pb       = $27
zp_g        = $28           ; logo x position (pixels)
zp_gr       = $29
zp_c8       = $2a
zp_wp       = $2b           ; (2) -> wave amplitude page
zp_ap       = $2d           ; (2) -> sinamp page
zp_fade     = $2f           ; 0..5
zp_ftick    = $30
zp_exit     = $31           ; 0 running, 1 fading out, 2 finished
zp_vol      = $32
zp_ftask    = $33
zp_fbase    = $34           ; fade level * 16
zp_nbars    = $35
zp_btick    = $36
zp_bph      = $37           ; (6) copper bar phases
zp_sxs      = $3d           ; scroller fine x (0..7)
zp_half     = $3e
zp_sp       = $3f           ; (2) scroll text pointer
zp_tp       = $41           ; (2) -> wave sample table of this frame
zp_pwh      = $43           ; wave phase / 8
zp_g8       = $44           ; G - 8
zp_g40      = $45           ; G + 24
zp_c8b      = $46           ; 8 * coarse shift of the current row
zp_by       = $47           ; (6) previous copper bar positions
zp_v1       = $4d
zp_v0       = $4e
zp_sbuf     = $4f           ; visible scroller screen (0/1)
zp_tick     = $50
zp_k        = $51
zp_spph     = $52
zp_sprc     = $53
zp_shc      = $54           ; glint counter
zp_e        = $55

frame_ge .macro             ; carry set if frame >= \1
        lda zp_frame+1
        cmp #>\1
        bne +
        lda zp_frame
        cmp #<\1
+
        .endm

; ============================================================================
update:
        .if DEBUG_CPU
        lda #2
        sta $d020
        .fi
        jsr MUSIC_PLAY
        lda zp_vol
        ora #$30
        sta $d418
        inc zp_frame            ; frame counter; the high byte cycles through $40..$7f
        bne +                   ;  after a few minutes so that all "frame >= T" tests stay
        inc zp_frame+1          ;  true while frame & 3 keeps its rhythm
        bpl +
        lda #$40
        sta zp_frame+1
+       jsr do_input
frame_logic:
        jsr do_timeline
        jsr do_logo
        jsr do_scroller
        jsr do_bars
        jsr do_fade_tasks
        jsr patch_dtab
        jsr set_entries
        jsr do_sprites
        jsr do_shine
        .if DEBUG_CPU
        lda #0
        sta $d020
        .fi
        rts

; ---------------------------------------------------------------------------
do_input:
        lda zp_exit
        bne +
        lda #$7f                ; space bar: column 7, row 4
        sta $dc00
        lda $dc01
        and #$10
        bne +
        lda #1
        sta zp_exit
        lda #0
        sta zp_ftick
+       rts

; A = signed sine(X) * level(A)      (level 0..16)
sinamp: clc
        adc #>amptab
        sta zp_ap+1
        txa
        tay
        lda (zp_ap),y
        rts

fade_changed:
        lda zp_fade
        asl
        asl
        asl
        asl
        sta zp_fbase
        lda #0
        sta zp_ftask
        rts

; ---------------------------------------------------------------------------
do_timeline:
        lda zp_py
        clc
        adc #SPD_Y
        sta zp_py
        lda zp_px
        clc
        adc #SPD_X
        sta zp_px
        lda zp_pw
        clc
        adc #SPD_W
        sta zp_pw
        lda zp_pb
        clc
        adc #SPD_B
        sta zp_pb

        lda zp_exit
        bne tl_out
        #frame_ge T_FADEIN
        bcc tl_ramps
        lda zp_fade
        cmp #5
        bcs tl_ramps
        inc zp_ftick
        lda zp_ftick
        cmp #FADE_IN_SPEED
        bcc tl_ramps
        lda #0
        sta zp_ftick
        inc zp_fade
        jsr fade_changed
        jmp tl_ramps
tl_out: lda zp_fade
        beq tl_fin
        inc zp_ftick
        lda zp_ftick
        cmp #FADE_OUT_SPEED
        bcc tl_ramps
        lda #0
        sta zp_ftick
        dec zp_fade
        jsr fade_changed
        jmp tl_ramps
tl_fin: lda zp_exit
        cmp #2
        beq tl_ramps
        inc zp_ftick
        lda zp_ftick
        cmp #40                 ; a short moment of black before we leave
        bcc tl_ramps
        lda #2
        sta zp_exit

tl_ramps:
        lda zp_fade             ; music volume follows the fade (0..15)
        asl
        clc
        adc zp_fade
        sta zp_vol

        lda zp_frame            ; one amplitude step every 8th frame
        and #$07
        bne tl_bars
        #frame_ge T_YMOVE
        bcc +
        lda zp_ay
        cmp #AY_MAX
        bcs +
        inc zp_ay
+       #frame_ge T_XMOVE
        bcc +
        lda zp_ax
        cmp #AX_MAX
        bcs +
        inc zp_ax
+       #frame_ge T_WAVE
        bcc +
        lda zp_aw
        cmp #AW_MAX
        bcs +
        lda zp_frame            ; the wave grows slower
        and #$0f
        bne +
        inc zp_aw
+       #frame_ge T_BOB
        bcc +
        lda zp_ab
        cmp #AB_MAX
        bcs +
        inc zp_ab
+
tl_bars:
        #frame_ge T_BARS
        bcc +
        lda zp_nbars
        cmp #NBARS
        bcs +
        inc zp_btick
        lda zp_btick
        cmp #BAR_SPEED
        bcc +
        lda #0
        sta zp_btick
        inc zp_nbars
+       rts

; ---------------------------------------------------------------------------
;  logo: vertical position (lead-in length), horizontal position per char row
;  (screen buffer) and per raster line pair (fine scroll = wave)
;    t  = 8 + wave                    (from wavet, unsigned)
;    p  = t + G - 8                   x position of the row centre
;    8c = p & $f8                     coarse shift of the row (screen buffer c)
;    idx= t + (G + 24 - 8c)           = fine + 32  -> clamp[] -> $d016
; ---------------------------------------------------------------------------
logo_row .macro             ; \1 = char row 0..6
        lda zp_pwh              ; centre sample: pair 4*row+2
        clc
        adc #4*\1+2
        tay
        lda (zp_tp),y
        clc
        adc zp_g8
        cmp #56
        bcc +
        lda #55
+       and #$f8
        sta zp_c8b
        asl
        clc
        adc #D018_LOGO          ; screen buffer = $40 + 16*c
        sta rowd018+\1
        lda zp_g40
        sec
        sbc zp_c8b
        sta zp_gr
        lda zp_pwh
        clc
        adc #4*\1
        tay
        clc
        .for l = 0, l < 8, l += 2
        lda (zp_tp),y
        adc zp_gr               ; carry stays clear: no overflow
        tax
        lda clamp,x
        sta wave+8*\1+l
        sta wave+8*\1+l+1
        iny
        .next
        .endm

do_logo:
        ldx zp_py               ; S = raster line of the first logo row
        lda zp_ay
        jsr sinamp
        clc
        adc #S_CENTER
        sta zp_tmp
        sec
        sbc #48
        sta zp_n
        lda zp_tmp
        clc
        adc #9
        sta zp_ymid
        ldx zp_px               ; G = x position in pixels
        lda zp_ax
        jsr sinamp
        clc
        adc #G_CENTER
        sta zp_g
        sec
        sbc #8
        sta zp_g8
        lda zp_g
        clc
        adc #24
        sta zp_g40
        lda zp_pw               ; wave sample table for (level, phase & 7)
        lsr
        lsr
        lsr
        sta zp_pwh
        lda zp_pw
        and #$07
        sta zp_c8
        lda zp_aw
        asl
        asl
        asl
        ora zp_c8               ; level*8 + r  (0..55)
        pha
        lsr
        lsr
        clc
        adc #>wavet
        sta zp_tp+1
        pla
        and #$03
        tax
        lda lo64,x
        sta zp_tp
        #logo_row 0
        #logo_row 1
        #logo_row 2
        #logo_row 3
        #logo_row 4
        #logo_row 5
        #logo_row 6
        lda rowd018
        sta zp_d018r0
        rts

; ---------------------------------------------------------------------------
;  scroller
; ---------------------------------------------------------------------------
do_scroller:
        ldx zp_pb               ; S2 = raster line of the scroller
        lda zp_ab
        jsr sinamp
        clc
        adc #S2_CENTER
        sta zp_tmp2
        sec
        sbc zp_tmp
        sbc #57
        sta zp_m                ; mid FLD cells = S2 - S - 57
        #frame_ge T_SCROLL
        bcc sc_prep
        lda zp_sxs
        sec
        sbc #SCROLL_SPEED
        bcs sc_nowrap
        adc #8
        sta zp_sxs
        lda zp_sbuf             ; the hidden screen becomes visible
        eor #$01
        sta zp_sbuf
        tax
        lda d018buf,x
        sta zp_d018sc
        jmp sc_prep
sc_nowrap:
        sta zp_sxs
sc_prep:
        lda zp_sxs
        ora #$08
        sta zp_d016sc
        #frame_ge T_SCROLL-4    ; build the next screen (chunk 0,1,2 in frames 3,0,1)
        bcc sc_done
        lda zp_frame
        and #$03
        cmp #$02
        beq sc_done
        clc
        adc #1
        and #$03                ; frame 3,0,1 -> chunk 0,1,2
        sta zp_tick
        lda zp_sbuf
        asl
        adc zp_sbuf
        adc zp_tick
        asl
        tax
        lda sctab+1,x
        pha
        lda sctab,x
        pha
sc_done:
        rts

; ---------------------------------------------------------------------------
;  double buffered shift: the hidden screen is built in 3 chunks of 13 columns
;  (frames 3,0,1 of every 4), then displayed by switching $d018 at frame 3
; ---------------------------------------------------------------------------
sc_chunk .macro             ; \1 = source screen, \2 = destination, \3..\4 = columns
        .for c = \3, c <= \4, c += 1
        lda \1+280+1+c
        sta \2+280+c
        lda \1+320+1+c
        sta \2+320+c
        .next
        .endm

sc_insert .macro            ; \1 = destination screen: new column 39
        ldy #0
        lda (zp_sp),y
        bne +
        lda #<scrolltext
        sta zp_sp
        lda #>scrolltext
        sta zp_sp+1
        lda (zp_sp),y
+       tax
        lda font_map,x
        asl
        asl                     ; code of the top-left tile
        ldx zp_half
        beq +
        ora #$01                ; right half: top-right
+       sta \1+280+39
        ora #$02                ; bottom row
        sta \1+320+39
        lda zp_half
        eor #$01
        sta zp_half
        bne +
        inc zp_sp
        bne +
        inc zp_sp+1
+
        .endm

sc0a:   #sc_chunk SCR_SCROLL, SCR_SCROLL2, 0, 12
        rts
sc0b:   #sc_chunk SCR_SCROLL, SCR_SCROLL2, 13, 25
        rts
sc0c:   #sc_chunk SCR_SCROLL, SCR_SCROLL2, 26, 38
        #sc_insert SCR_SCROLL2
        rts
sc1a:   #sc_chunk SCR_SCROLL2, SCR_SCROLL, 0, 12
        rts
sc1b:   #sc_chunk SCR_SCROLL2, SCR_SCROLL, 13, 25
        rts
sc1c:   #sc_chunk SCR_SCROLL2, SCR_SCROLL, 26, 38
        #sc_insert SCR_SCROLL
        rts
sctab   .word sc0a-1, sc0b-1, sc0c-1, sc1a-1, sc1b-1, sc1c-1
d018buf .byte D018_SCROLL, D018_SCROLL+$10

; ---------------------------------------------------------------------------
;  copper bars: erase the old positions, stamp the new ones (colours: barpal)
; ---------------------------------------------------------------------------
BSPEED  = [3, 4, 2, -3, -4, -2]

bars_half .macro            ; \1 = 0: bars 0,2,4   1: bars 1,3,5
        lda #0
        .for b = \1, b < NBARS, b += 2
        ldy zp_by+b
        .for k = 0, k < BARLEN, k += 1
        sta bar+k,y
        .next
        .next
        .for b = \1, b < NBARS, b += 2
        lda zp_bph+b
        clc
        adc #(BSPEED[b] * 2) & $ff
        sta zp_bph+b
        lda zp_nbars
        cmp #b+1
        bcc +
        ldx zp_bph+b
        lda barsin,x
        clc
        adc #BAR_TOP
        tay
        sty zp_by+b
        .for k = 0, k < BARLEN, k += 1
        lda barpal+b*BARLEN+k
        sta bar+k,y
        .next
+
        .next
        .endm

; three bars per frame: bars 0,2,4 on even frames, 1,3,5 on odd frames
;  (each bar is repainted every second frame, the load is the same every frame)
do_bars:
        lda zp_frame
        and #$01
        beq +
        jmp bars_odd
+       #bars_half 0
        rts
bars_odd:
        #bars_half 1
        rts


; ---------------------------------------------------------------------------
;  special $d011 table entries (see intro.asm):  zp_n, zp_tmp = S, zp_tmp2 = S2
; ---------------------------------------------------------------------------
patch_dtab:
        ldx zp_oldn             ; restore last frame's entries from the pattern
        lda dtabpat,x
        sta dtab,x
        ldx zp_olds2
        lda dtabpat,x
        sta dtab,x
        ldx zp_n                ; T1 writes S&7: starts the first bad line
        stx zp_oldn
        lda zp_tmp
        and #$07
        ora #$18
        sta dtab,x
        lda zp_tmp              ; the last logo cell writes (S+1)&7
        clc
        adc #1
        and #$07
        ora #$18
        sta zp_dlast
        lda zp_tmp2             ; the last mid cell (S2-2) starts the scroller's bad line
        and #$07
        ora #$18
        sta zp_v1
        and #$f7
        sta zp_v0               ; (RSEL=0 variant from raster line 249 on)
        lda zp_tmp2
        sec
        sbc #48
        tax
        stx zp_olds2
        lda zp_v1
        sta dtab,x
        ; dsctab[k] : cell k is at raster line S2-1+k; RSEL=0 from line 249 on
        lda zp_v1
        .for k = 0, k < 16, k += 1
        sta dsctab+k
        .next
        lda #250                ; first k with RSEL=0: 250 - S2   (3 .. 27)
        sec
        sbc zp_tmp2
        cmp #16
        bcs dsc_done
        tax
        lda zp_v0
-       sta dsctab,x
        inx
        cpx #16
        bne -
dsc_done:
        lda zp_tmp2             ; first scroller cell takes its colour from the bar table
        sec
        sbc #47
        tax
        lda plate
        sta bar,x
        rts

set_entries:
        ldx zp_n
        lda leadp_lo,x
        sta zp_ent
        lda leadp_hi,x
        sta zp_ent+1
        ldx zp_m
        lda midp_lo,x
        sta zp_midp
        lda midp_hi,x
        sta zp_midp+1
        rts

; ---------------------------------------------------------------------------
;  glint: a bright band runs down the logo face (every 2nd frame, 52 steps,
;  then a pause).  It only rewrites a few entries of grad[].
; ---------------------------------------------------------------------------
SHINE_STEPS = 52
SHINE_PAUSE = 70

restore_grad .macro         ; grad[\1 + Y] = faded gradsrc[\1 + Y]
        lda gradsrc+\1,y
        ora zp_fbase
        tax
        lda fadetab,x
        sta grad+\1,y
        .endm

do_shine:
        lda zp_frame
        and #$01
        bne shn_ret
        lda zp_fade             ; only once the logo is fully faded in
        cmp #5
        bne shn_ret
        lda zp_shc
        cmp #SHINE_STEPS
        bcs shn_idle
        tay                     ; y = position of the band (0 .. SHINE_STEPS-1)
        beq +
        dey                     ; restore the entry the band just left
        #restore_grad 0
        iny
+       lda #3                  ; glint colours (faded): cyan, white, white, cyan
        ora zp_fbase
        tax
        lda fadetab,x
        sta zp_e
        lda #1
        ora zp_fbase
        tax
        lda fadetab,x
        sta grad+1,y
        sta grad+2,y
        lda zp_e
        sta grad,y
        sta grad+3,y
        inc zp_shc
shn_ret:
        rts
shn_idle:
        bne shn_pause
        ldy #SHINE_STEPS-1      ; first idle call: clear the last band
        #restore_grad 0
        #restore_grad 1
        #restore_grad 2
        #restore_grad 3
shn_pause:
        inc zp_shc
        lda zp_shc
        cmp #SHINE_STEPS+SHINE_PAUSE
        bcc shn_ret
        lda #0
        sta zp_shc
        rts

; ---------------------------------------------------------------------------
;  credit text sprites: y wave every frame, colours every 4th frame
; ---------------------------------------------------------------------------
sprpal  .byte 6, 6, 14, 14, 3, 3, 1, 1, 1, 3, 3, 14, 14, 6, 6, 6

do_sprites:
        lda zp_frame
        and #$01
        beq +
        jmp spr_col             ; y wave: every second frame
+
        .for k = 0, k < 7, k += 1
        lda zp_spph
        clc
        adc #k*32
        tax
        lda sprsin,x
        sta $d001+2*k
        .next
        lda zp_spph
        clc
        adc #12
        sta zp_spph
spr_col:
        lda zp_frame            ; colours: a rainbow that walks along the text
        and #$03
        beq +
        rts
+       .for k = 0, k < 7, k += 1
        lda zp_sprc
        clc
        adc #2*k
        and #$0f
        tax
        lda sprpal,x
        ora zp_fbase
        tax
        lda fadetab,x
        sta $d027+k
        .next
        inc zp_sprc
        rts

; ---------------------------------------------------------------------------
;  fading: 16 small jobs, two per frame, started by every level change
; ---------------------------------------------------------------------------
NFT = 16
do_fade_tasks:
        jsr ft_one
ft_one: lda zp_ftask
        cmp #NFT
        bcs ft_idle
        inc zp_ftask
        asl
        tax
        lda fttab+1,x
        pha
        lda fttab,x
        pha
ft_idle:
        rts
fttab   .word ft0-1, ft1-1, ft2-1, ft3-1, ft4-1, ft5-1, ft6-1, ft7-1
        .word ft8-1, ft9-1, ft10-1, ft11-1, ft12-1, ft13-1, ft14-1, ft15-1

ft_bar  .macro                  ; bar palette \1
        ldy #BARLEN-1
-       lda barsrc+\1*BARLEN,y
        ora zp_fbase
        tax
        lda fadetab,x
        sta barpal+\1*BARLEN,y
        dey
        bpl -
        rts
        .endm
ft0:    #ft_bar 0
ft1:    #ft_bar 1
ft2:    #ft_bar 2
ft3:    #ft_bar 3
ft4:    #ft_bar 4
ft5:    #ft_bar 5

ft6:    ldy #15                 ; plate and $d022
-       lda platesrc,y
        ora zp_fbase
        tax
        lda fadetab,x
        sta plate,y
        dey
        bpl -
        lda #EXTR_COL
        ora zp_fbase
        tax
        lda fadetab,x
        sta $d022
        rts

ft_grad .macro                  ; face gradient lines \1 .. \1+13
        ldy #\1+13
-       lda gradsrc,y
        ora zp_fbase
        tax
        lda fadetab,x
        sta grad,y
        dey
        cpy #(\1-1) & $ff
        bne -
        rts
        .endm
ft7:    #ft_grad 0
ft8:    #ft_grad 14
ft9:    #ft_grad 28
ft10:   #ft_grad 42

ft_rim  .macro                  ; logo rim light, colour RAM cells \1 .. \1+69
        ldx zp_fade
        lda hlcol,x
        ora #$08
        .for i = 0, i < 70, i += 1
        sta $d800+\1+i
        .next
        rts
        .endm
ft11:   #ft_rim 0
ft12:   #ft_rim 70
ft13:   #ft_rim 140
ft14:   #ft_rim 210

ft15:   lda #scr_col_top        ; scroller text colours
        ora zp_fbase
        tax
        lda fadetab,x
        .for i = 0, i < 40, i += 1
        sta $d800+280+i
        .next
        lda #scr_col_bot
        ora zp_fbase
        tax
        lda fadetab,x
        .for i = 0, i < 40, i += 1
        sta $d800+320+i
        .next
        rts

hlcol   .byte 0, 0, 6, 6, 3, 1  ; rim light: black .. white, colours 0..7 only
