# Compressing the intro – research and results

The uncompressed intro is a 49,665 byte PRG (196 disk blocks). Loading that from a real 1541 with the stock
KERNAL loader takes minutes, so the released files are **self-extracting**: they load 9,490 bytes (38 blocks),
decrunch themselves in about 2.7 seconds and start the intro. All compression happens at build time; the
only code that runs on the C64 is the cruncher's own decompressor.

| file | size | disk blocks |
|---|---|---|
| unpacked `build/intro.prg` (development only, not distributed) | 49,665 bytes | 196 |
| self-extracting `build/breeze.prg` = `release/breeze-intro.prg` | **9,490 bytes** | **38** |

## 1. What the C64 scene uses

Research (forum threads, the crunchers' own repositories) shows a fairly stable picture. The main families:

| cruncher | kind | typical use / characteristics |
|---|---|---|
| **Exomizer** (Magnus Lind) | LZ77 + entropy coded (bit stream) | the "default" for demos and games: best or near-best ratio, ready-made self-extracting PRG mode, decrunch is comparatively slow |
| **ZX0 / Dali** (Einar Saukas, Bitnax) | optimal LZ with a very compact bit format | ratio close to Exomizer, decompressor is tiny and much faster |
| **TSCrunch** (Antonio Savona) | optimal byte-aligned LZ + RLE | designed for decompression speed (fastest on NMOS 6502), 248 byte decompressor, worse ratio because it is byte oriented |
| **ByteBoozer 2**, **Doynamite** (Doynax LZ), **Bitnax** | LZ variants | often recommended as a good balance of speed and size for demo parts |
| **KabutoCrunch** | ZX0-style coding + TSCrunch-like explicit RLE | newer, small decompressor |
| **Pucrunch** | LZ77 + RLE + Huffman-like coding | the classic; superseded in ratio by Exomizer |

Rules of thumb that came out of the research:

* Bit-oriented crunchers (Exomizer, ZX0, ByteBoozer) win on **size**; byte-aligned ones (TSCrunch) win on **speed**.
  TSCrunch's author states it is typically 20–40 % faster to decode than comparable byte crunchers but loses on
  efficiency against Exomizer/ByteBoozer2.
* For a one-shot start-up (crunch once, decrunch once), size matters more than decrunch speed: the disk load is
  many times slower than any decompressor. Speed matters for streaming assets in games.
* Exomizer is the safe default; ZX0/Dali is the strong alternative if decrunch time matters.

Sources:

* TSCrunch – https://github.com/tonysavon/TSCrunch (design, benchmarks, SFX mode)
* KabutoCrunch – https://github.com/tonysavon/kabutocrunch/
* CSDb thread on TSCrunch – https://csdb.dk/forums/?roomid=12&topicid=155140&firstpost=3
* ZX0 – https://github.com/einar-saukas/ZX0
* Exomizer (sfx mode, `-Di_load_addr`, forum discussion) – https://www.lemon64.com/forum/viewtopic.php?t=77363 ,
  https://csdb.dk/forums/?roomid=11&topicid=142282 , https://www.c64-wiki.de/wiki/Exomizer
* Cruncher recommendation threads – https://csdb.dk/forums/?roomid=7&topicid=30008&showallposts=1 ,
  https://www.lemon64.com/forum/viewtopic.php?p=746373 , https://stardot.org.uk/forums/viewtopic.php?t=27861
  (comparison table of 6502 decompressors)

## 2. What was measured

Input: the real program image, 49,663 bytes from `$0801` to `$C9FF`. The assembler fills the gaps between the
segments with zeros, 37 % of the image is zero fill, which every cruncher removes almost for free.
Crunchers were built or installed on the development Mac (Exomizer 3.1.2 from Homebrew, ZX0 and TSCrunch 1.3.2
compiled from their C sources) and run on the same file:

| method | size in bytes | note |
|---|---|---|
| Exomizer 3 `raw` | 8,949 | data only, needs a decompressor |
| ZX0 | 9,059 | data only, needs a decompressor |
| TSCrunch | 12,040 | data only |
| Exomizer 3 `sfx` (default effect) | 9,487 | complete self-extracting PRG |
| Exomizer 3 `sfx`, no effect, screen blanked (**used**) | **9,490** | complete self-extracting PRG |
| TSCrunch `-x` self-extracting | 12,271 | complete self-extracting PRG |
| *xz (LZMA), reference only* | 8,076 | not usable on a 6510 |
| *zlib -9 / bzip2, reference only* | 10,399 / 11,111 | not usable on a 6510 |

Exomizer's SFX file is only ~540 bytes larger than the raw data: that is the BASIC `SYS` line plus the
decompressor and its tables. A hand-made ZX0 start-up stub would save perhaps 500 bytes but would have to be
written and maintained; it was not worth it.

### Where the remaining 9 KB go

Each segment crunched on its own (Exomizer raw), so the numbers add up to slightly more than the whole file:

| segment | raw | crunched |
|---|---|---|
| SID music (`$1000`) | 3,469 | 2,217 |
| update code + tables + scroll text (`$2000`–`$3FFF`) | 8,192 | 3,369 |
| scroller font charset | 2,048 | 938 |
| raster block + IRQ code (`$8000`–`$AAFF`) | 11,008 | 605 |
| sine tables (17 pages) | 4,352 | 420 |
| logo charset | 2,048 | 371 |
| boot code and page `$08` | 2,047 | 401 |
| wave tables | 3,584 | 240 |
| logo screens (7 shifted copies) | 7,168 | 215 |
| scroller screens, sprite data, gaps | 5,120 | 134 |

The large tables are already tiny after crunching (they are regular, and the seven shifted logo screens are almost
copies of each other), so generating them at run time would save well under 1 KB. The music (2.2 KB) is
essentially incompressible. The practical floor is about 8.9 KB.

## 3. How it is built

`make packed` (see the `Makefile`):

```sh
exomizer sfx sys -q -n \
  -s "$(printf 'lda #$0b\nsta $d011\nlda #0\nsta $d020')" \
  build/intro.prg -o build/breeze.prg
```

* `sfx sys` – writes a BASIC stub with a `SYS` line, detected from the input PRG's own stub; the decrunched
  program is started where that stub points to (`$0810`), so the intro's own start-up code is unchanged.
* `-n` – no border-flash effect while decrunching.
* `-s` – code executed when the decruncher starts: blank the screen and black border. The VIC then does not steal
  bad-line cycles from the CPU, which shortens the decrunch by about 5 %.

`make disk` writes `build/breeze.prg` to a d64 with `c1541` (the file is named `BREEZE`). The files in
`release/` are exactly those two outputs. The unpacked PRG is only used for development (the tools
`tools/profile.py`, `tools/cyc.py`, the trace tools work on it); it is not distributed.

## 4. Decrunch time

Measured in VICE as emulated cycles between the start of the `SYS` stub (`$080D`) and the first execution of the
intro's IRQ code (`$8000`):

| variant | cycles | seconds (PAL, 985,248 Hz) |
|---|---|---|
| Exomizer default effect | 2,849,491 | 2.89 |
| `-n`, screen blanked (used) | ~2,694,000 | 2.73 |

On a real machine this is small compared with loading: the stock 1541 loader delivers roughly 350 bytes/s
(estimate, not measured here), i.e. ~2 min 20 s for the unpacked file against ~30 s for the packed one plus the
3 s decrunch. With a fast loader the ratio stays the same.

## 5. Verifying that nothing is lost

`tools/verify_packed.py` starts `build/breeze.prg` in VICE (remote monitor), waits until the intro is running, reads
back RAM `$0801`–`$C9FF` through the monitor and compares every region that the intro never modifies at run time
(raster block, wave and sine tables, charsets, logo screens, sprite data, update code, boot code) byte for byte
with the unpacked build. All regions are identical. The packed d64 was also booted through VICE's emulated 1541
drive (true drive emulation) and runs normally.

## 6. Ideas that were considered and dropped

* **ZX0/Dali or TSCrunch with our own stub** – 1–2 s faster start, but it has to be written by hand and the file is not
  smaller (TSCrunch is 30 % bigger).
* **Generating tables at run time** (sine, wave, shifted logo screens) – saves well under 1 KB, costs code and start-up time.
* **Shortening the music** – not our data.
* **Fast loader** – outside the scope of the intro file; a loader/fastloader would improve real-drive loading further, independent
  of the compression.

## 7. Reproducing the benchmark

```sh
brew install exomizer
git clone https://github.com/einar-saukas/ZX0.git && (cd ZX0/src && cc -O2 -o ../zx0 zx0.c compress.c optimize.c memory.c)
git clone https://github.com/tonysavon/TSCrunch.git && cc -O2 -o tsc TSCrunch/tscrunch.c
make                                    # build/intro.prg
tail -c +3 build/intro.prg > raw.bin    # drop the 2 byte load address
exomizer raw -q raw.bin -o ex.bin ;  ZX0/zx0 -f raw.bin z.bin ;  ./tsc -q -p build/intro.prg ts.bin
ls -l ex.bin z.bin ts.bin
```
