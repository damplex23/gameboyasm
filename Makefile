AS := as
LD := ld
ASFLAGS := --64 -g -I .
LDFLAGS := -static -z noexecstack

.PHONY: all clean test demo
all: build/gameboy build/demo.gb

build:
	mkdir -p build

build/gameboy.o: src/main.s src/state.s src/cpu.s src/memory.s src/ppu.s src/linux.s | build
	$(AS) $(ASFLAGS) -o $@ $<

build/gameboy: build/gameboy.o
	$(LD) $(LDFLAGS) -o $@ $<

build/demo.o: roms/demo.s roms/gb.inc | build
	$(AS) $(ASFLAGS) -o $@ $<

build/demo.gb: build/demo.o
	$(LD) -Ttext=0 --oformat=binary -e 0 -o $@ $<

build/tests.o: tests/tests.s src/state.s src/cpu.s src/memory.s src/ppu.s src/linux.s | build
	$(AS) $(ASFLAGS) -o $@ $<

build/tests: build/tests.o
	$(LD) $(LDFLAGS) -o $@ $<

test: all build/tests
	./build/tests
	./build/gameboy build/demo.gb --frames 120 --dump build/demo.pgm > build/demo.serial
	grep -qx 'ASM OK' build/demo.serial
	test "$$(wc -c < build/demo.pgm)" -eq 23055
	! readelf -l build/gameboy | grep -q INTERP
	! readelf -d build/gameboy | grep -q NEEDED

demo: all
	./build/gameboy build/demo.gb

clean:
	rm -rf build
