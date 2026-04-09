# fw/Makefile
# Run from WSL2. Requires: riscv64-unknown-elf-gcc, python3, make.

# ── Toolchain ─────────────────────────────────────────────────────────────
CROSS   := riscv64-unknown-elf
CC      := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
OBJDUMP := $(CROSS)-objdump
NM      := $(CROSS)-nm
SIZE    := $(CROSS)-size

# ── Architecture flags ─────────────────────────────────────────────────────
# RV32IMC: Integer + Multiply + Compressed 16-bit instructions
ARCH    := -march=rv32imc -mabi=ilp32

# ── Source files ───────────────────────────────────────────────────────────
SRCS    := start.S main.c i2c_driver.c

# ── Build flags ────────────────────────────────────────────────────────────
CFLAGS  := $(ARCH) -nostdlib -ffreestanding -O1 -Wall -Wextra
LDFLAGS := -T link.ld -nostdlib

# ── Quartus project directory (Windows path accessible from WSL2) ──────────
QUARTUS_DIR := /mnt/c/projects/picorv32-soc

# ── Default target ─────────────────────────────────────────────────────────
.PHONY: all clean dump size symbols

all: fw.mif

# ── Link ELF ───────────────────────────────────────────────────────────────
fw.elf: $(SRCS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)

# ── Strip to raw binary ────────────────────────────────────────────────────
fw.bin: fw.elf
	$(OBJCOPY) -O binary $< $@

# ── Convert to MIF for Quartus altsyncram ─────────────────────────────────
fw.mif: fw.bin
	python3 bin2mif.py $< $@
	@echo "MIF generated: $@"
	@# Copy to Quartus project directory if it exists
	@if [ -d "$(QUARTUS_DIR)" ]; then \
	    cp $@ $(QUARTUS_DIR)/$@; \
	    echo "Copied to $(QUARTUS_DIR)"; \
	fi

# ── Utility targets ────────────────────────────────────────────────────────
dump: fw.elf
	$(OBJDUMP) -d -M no-aliases $<

size: fw.elf
	$(SIZE) -A $<

symbols: fw.elf
	$(NM) -n $<

clean:
	rm -f *.o fw.elf fw.bin fw.mif
