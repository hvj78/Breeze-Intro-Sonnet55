#!/bin/sh
# Build (if needed) and run the intro in VICE (macOS / Homebrew: brew install vice 64tass)
set -e
cd "$(dirname "$0")"
make
exec x64sc -VICIIborders 0 -autostartprgmode 1 -autostart build/intro.prg
