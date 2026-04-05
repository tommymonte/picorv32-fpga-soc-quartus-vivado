# `fw/Makefile` and `fw/bin2mif.py` — Build System

---

## `fw/Makefile`

### Role in the System

The Makefile orchestrates the entire firmware build pipeline in WSL2:

```
start.S + main.c + i2c_driver.c
        │
        ▼ (riscv64-unknown-elf-gcc)
      fw.elf
        │
        ▼ (riscv64-unknown-elf-objcopy)
      fw.bin
        │
        ▼ (python3 bin2mif.py)
      fw.mif  ──── cp ──►  /mnt/c/projects/picorv32-soc/fw.mif
```

### Implementation

```makefile
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
OBJS    := $(SRCS:.S=.o)
OBJS    := $(OBJS:.c=.o)

# ── Build flags ────────────────────────────────────────────────────────────
CFLAGS  := $(ARCH) -nostdlib -ffreestanding -O1 -Wall -Wextra
LDFLAGS := -T link.ld -nostdlib

# ── Quartus project directory (Windows path accessible from WSL2) ──────────
QUARTUS_DIR := /mnt/c/projects/picorv32-soc

# ── Default target ─────────────────────────────────────────────────────────
.PHONY: all clean dump size

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

# ── Individual object files ────────────────────────────────────────────────
%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# ── Utility targets ────────────────────────────────────────────────────────
dump: fw.elf
	$(OBJDUMP) -d -M no-aliases $<

size: fw.elf
	$(SIZE) -A $<

symbols: fw.elf
	$(NM) -n $<

clean:
	rm -f *.o fw.elf fw.bin fw.mif
```

### Important Flags Explained

| Flag | Meaning |
|------|---------|
| `-march=rv32imc` | Target RV32 with Integer, Multiply, Compressed extensions |
| `-mabi=ilp32` | ABI: int/long/pointer = 32-bit, no float in registers |
| `-nostdlib` | Do not link libc, libgcc, or crt0 |
| `-ffreestanding` | No standard library assumptions; `main` has no special meaning to the compiler |
| `-O1` | Light optimization: eliminates dead code but keeps debugging easy |
| `-T link.ld` | Use our custom linker script |

---

## `fw/bin2mif.py`

### Role in the System

Converts the raw binary firmware image (`fw.bin`) into Intel MIF format (`fw.mif`), which Quartus reads to initialize the `altsyncram` M10K blocks.

### MIF Format

```
DEPTH = 4096;           -- Number of words
WIDTH = 32;             -- Bits per word
ADDRESS_RADIX = HEX;
DATA_RADIX = HEX;

CONTENT BEGIN
  0000 : 00000093;      -- Address 0, data (little-endian 32-bit word)
  0001 : 00000113;
  ...
  03FF : 00000000;      -- Last word
  [0400..0FFF] : 00000000;  -- Uninitialized words → zero
END;
```

### Endianness

RISC-V is **little-endian**. The binary file stores bytes in memory order:
- `fw.bin[0]` = byte at address `0x00000000`
- `fw.bin[3]` = byte at address `0x00000003`

A 32-bit word at address `0x00000000` is:
```
fw.bin[0] = LSB (byte 0)
fw.bin[1] = byte 1
fw.bin[2] = byte 2
fw.bin[3] = MSB (byte 3)

MIF word = (fw.bin[3] << 24) | (fw.bin[2] << 16) | (fw.bin[1] << 8) | fw.bin[0]
```

### Implementation

```python
#!/usr/bin/env python3
"""
bin2mif.py — Convert raw binary firmware to Intel MIF format.

Usage:
    python3 bin2mif.py fw.bin fw.mif

Output:
    MIF file with DEPTH=4096, WIDTH=32, little-endian word packing.
"""

import sys
import struct

RAM_WORDS   = 4096          # 16 KB / 4 bytes per word
WORD_BYTES  = 4

def bin2mif(bin_path: str, mif_path: str) -> None:
    with open(bin_path, 'rb') as f:
        data = f.read()

    # Pad to full RAM size with zeros
    data = data.ljust(RAM_WORDS * WORD_BYTES, b'\x00')

    if len(data) > RAM_WORDS * WORD_BYTES:
        print(f"ERROR: Binary ({len(data)} bytes) exceeds RAM ({RAM_WORDS * WORD_BYTES} bytes)",
              file=sys.stderr)
        sys.exit(1)

    with open(mif_path, 'w') as f:
        # Header
        f.write(f"DEPTH = {RAM_WORDS};\n")
        f.write(f"WIDTH = {WORD_BYTES * 8};\n")
        f.write("ADDRESS_RADIX = HEX;\n")
        f.write("DATA_RADIX = HEX;\n")
        f.write("\n")
        f.write("CONTENT BEGIN\n")

        # Words
        for i in range(RAM_WORDS):
            offset = i * WORD_BYTES
            word_bytes = data[offset : offset + WORD_BYTES]

            # Little-endian: byte 0 is LSB
            word = struct.unpack('<I', word_bytes)[0]   # '<I' = little-endian uint32

            f.write(f"  {i:04X} : {word:08X};\n")

        f.write("END;\n")

    print(f"Written {mif_path} ({RAM_WORDS} words, {len(data)} bytes)")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.mif>", file=sys.stderr)
        sys.exit(1)
    bin2mif(sys.argv[1], sys.argv[2])
```

### Verification

After generating `fw.mif`, check the first few lines match the expected reset vector:

```bash
head -15 fw.mif
# Should see non-zero words at address 0000 (the _start code)

# Cross-check with objdump:
riscv64-unknown-elf-objdump -d fw.elf | head -20
# First instruction bytes should match MIF[0000]
```

---

## Build Workflow Summary

```bash
# In WSL2, from the fw/ directory:

# Full build + copy to Quartus:
make

# Just inspect sizes:
make size

# Disassembly listing:
make dump

# Clean and rebuild:
make clean && make

# Manual step-by-step (useful for debugging):
riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -ffreestanding \
    -T link.ld -o fw.elf start.S main.c i2c_driver.c
riscv64-unknown-elf-objcopy -O binary fw.elf fw.bin
python3 bin2mif.py fw.bin fw.mif
```

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Big-endian packing in `bin2mif.py` | Instructions execute as garbage | Use `struct.unpack('<I', ...)` (little-endian) |
| MIF `DEPTH` less than RAM size | Uninitialized words in Quartus M10K | Always write all `RAM_WORDS` words |
| Not copying `.mif` to Quartus project dir | Quartus uses stale firmware | Check `QUARTUS_DIR` path in Makefile |
| Compiling without `-march=rv32imc` | `trap` asserts on compressed instructions | Always match GCC arch to `picorv32` generic `COMPRESSED_ISA` |
| Using `-O2` or `-O3` | Aggressive optimization may eliminate volatile accesses | Use `-O1` for bare-metal peripheral code |
