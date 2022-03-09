# Copyright (C) 2012       Alejandro Mery <amery@geeks.cl>
# Copyright (C) 2012,2013  Henrik Nordstrom <henrik@henriknordstrom.net>
# Copyright (C) 2013       Patrick Wood <patrickhwood@gmail.com>
# Copyright (C) 2013       Pat Wood <Pat.Wood@efi.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Windows predefines OS in the environment (to "Windows_NT"), otherwise use uname
OS ?= $(shell uname)

PLATFORM=$(shell uname -m)

CC ?= gcc
DEFAULT_CFLAGS := -std=c99
DEFAULT_CFLAGS += -Wall -Wextra -Wno-unused-result

DEFAULT_CFLAGS += -D_POSIX_C_SOURCE=200112L
# Define _BSD_SOURCE, necessary to expose all endian conversions properly.
# See http://linux.die.net/man/3/endian
DEFAULT_CFLAGS += -D_BSD_SOURCE
# glibc 2.20+ also requires _DEFAULT_SOURCE
DEFAULT_CFLAGS += -D_DEFAULT_SOURCE
ifeq ($(OS),NetBSD)
# add explicit _NETBSD_SOURCE, see https://github.com/linux-sunxi/sunxi-tools/pull/22
DEFAULT_CFLAGS += -D_NETBSD_SOURCE
endif

DEFAULT_CFLAGS += -Iinclude/

LIBUSB = libusb-1.0

#HIDAPI = hidapi-libusb
HIDAPI = hidapi-hidraw
ifeq ($(OS),Windows_NT)
HIDAPI = hidapi
endif
ifeq ($(OS),Darwin)
HIDAPI = hidapi
endif

CFLAGS += $(shell pkg-config --cflags $(LIBUSB)) $(shell pkg-config --cflags $(HIDAPI))
LIBS   += $(shell pkg-config --libs $(LIBUSB))   $(shell pkg-config --libs $(HIDAPI))
.PHONY: all

all:
	$(CC) icesprog.c $(CFLAGS) $(LIBS) -o icesprog

test1:
	./icesprog -r -l 104090 out.bin

test2:
	./icesprog -r -o 0x100000 -l 104090 out.1M.bin

test3:
	./icesprog pwm.bin

dump:
	./icesprog -r -l 8388608 chip.bin

deploy:
	@if [ "$(PLATFORM)" = "x86_64" ]; then \
	    cp icesprog ~/oss/icesugar/tools/icesprog.x64; \
    elif [ "$(PLATFORM)" = "armv7l"  ]; then \
	    cp icesprog ~/oss/icesugar/tools/icesprog.arm32; \
    elif [ "$(PLATFORM)" = "aarch64"  ]; then \
	    cp icesprog ~/oss/icesugar/tools/icesprog.arm64; \
    fi
