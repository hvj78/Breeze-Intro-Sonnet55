# BREEZE intro build
$(shell mkdir -p build)
PY      := .venv/bin/python
ASM     := 64tass
ASMFLAGS:= -a -C --vice-labels -Wno-implied-reg

all: build/intro.prg

build/logo_charset.bin build/logo_screens.bin build/font_charset.bin build/font_map.inc build/sprites.bin: tools/gen_assets.py
	$(PY) tools/gen_assets.py

CFG ?=
build/config.inc: FORCE
	@printf 'DEBUG_BG := 0\nDEBUG_EDGE := 0\nDEBUG_CPU := 0\nSTAB_DELAY := 8\nSTAB_NOPS := 0\nSTAB_BIT := 1\nENTRY_PAD := 31\nENTRY_NOPS := 3\nENTRY_BIT := 0\n' > build/config.tmp
	@for kv in $(CFG); do printf '%s\n' "$$kv" | sed 's/=/ := /' >> build/config.tmp; done
	@if ! cmp -s build/config.tmp build/config.inc; then cp build/config.tmp build/config.inc; fi

FORCE:

music/magic.bin: music/Magic.sid tools/sid2bin.py
	python3 tools/sid2bin.py $< $@

build/intro.prg: src/intro.asm src/update.asm src/data.asm build/logo_charset.bin build/sprites.bin music/magic.bin build/config.inc
	$(ASM) $(ASMFLAGS) -l build/intro.lbl -L build/intro.lst -o $@ src/intro.asm
	$(PY) tools/cyc.py build/intro.lst

# self-extracting version (Exomizer 3: brew install exomizer).  The screen is blanked and the
# border set to black while it decrunches (~2.7 s); it then starts the intro at $0810.
build/breeze.prg: build/intro.prg
	exomizer sfx sys -q -n -s "$$(printf 'lda #$$0b\nsta $$d011\nlda #0\nsta $$d020')" $< -o $@

packed: build/breeze.prg

disk: build/breeze.prg
	c1541 -format "breeze,26" d64 build/breeze.d64 -write build/breeze.prg breeze >/dev/null

run: build/intro.prg
	x64sc -VICIIborders 0 -autostartprgmode 1 -autostart build/intro.prg

clean:
	rm -rf build

.PHONY: all run clean packed disk
