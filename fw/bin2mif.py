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
