# Cross-compile the OLED initramfs splash binary for arm64.
#
# Usage:
#     make                          # build for arm64 (default)
#     make HOST=1                   # build native (x86) — useful for
#                                   # syntax-checking on the build host
#                                   # without installing the cross-toolchain
#     make clean
#
# Requires:
#     - aarch64-linux-gnu-gcc       (Debian: gcc-aarch64-linux-gnu)
#     - python3 + python3-pil       (for gen-bitmap.py)
#     - fonts-dejavu-core           (for the bitmap font; optional fallback)
#
# Static link so the resulting binary has no .so dependencies and
# can be dropped into initramfs without dragging libc + ld-linux in.

ifeq ($(HOST),1)
CC ?= cc
TARGET = splash
else
CC = aarch64-linux-gnu-gcc
TARGET = splash.arm64
endif

CFLAGS = -Wall -Wextra -Wpedantic -Werror \
         -O2 -static \
         -std=c11 \
         -D_GNU_SOURCE

SRC = splash.c
HDR = splash_bitmap.h

all: $(TARGET)

$(TARGET): $(SRC) $(HDR)
	$(CC) $(CFLAGS) -o $@ $(SRC)
	@command -v size >/dev/null 2>&1 && size $@ || true

$(HDR): gen-bitmap.py
	python3 gen-bitmap.py $@

clean:
	rm -f splash splash.arm64 $(HDR)

.PHONY: all clean
