#!/usr/bin/env python3
"""
mif2coe.py — Convert Intel/Quartus MIF to Xilinx COE

Usage:
    python3 mif2coe.py  input.mif  output.coe

Vivado's Block Memory Generator uses .coe (Coefficient) files for initialisation;
Quartus uses .mif (Memory Initialization File). The formats differ only in
header syntax — the data values are identical.

MIF format (subset parsed here):
    DEPTH = <n>;
    WIDTH = <n>;
    ...
    CONTENT BEGIN
        <addr> : <hex_data>;        -- single address
        [<lo>..<hi>] : <hex_data>;  -- address range (all filled with same value)
    END;

COE format produced:
    memory_initialization_radix=16;
    memory_initialization_vector=
    <val0>,
    <val1>,
    ...
    <valN>;
"""

import sys
import re


def parse_mif(path: str) -> list[str]:
    """Return list of hex word strings in address order."""
    words: dict[int, str] = {}
    depth = 0
    width = 0
    in_content = False

    with open(path, "r") as f:
        for raw in f:
            line = raw.strip()
            # Strip inline comments
            if "--" in line:
                line = line[: line.index("--")].strip()
            if not line:
                continue

            upper = line.upper()

            if upper.startswith("DEPTH"):
                m = re.search(r"=\s*(\d+)", line)
                if m:
                    depth = int(m.group(1))

            elif upper.startswith("WIDTH"):
                m = re.search(r"=\s*(\d+)", line)
                if m:
                    width = int(m.group(1))

            elif upper == "CONTENT BEGIN":
                in_content = True

            elif upper in ("END;", "END"):
                in_content = False

            elif in_content and ":" in line:
                # Address : data;
                # [lo..hi] : data;
                line = line.rstrip(";").strip()
                addr_part, data_part = line.split(":", 1)
                addr_part = addr_part.strip()
                data_hex = data_part.strip()

                range_match = re.match(
                    r"\[\s*([0-9A-Fa-f]+)\s*\.\.\s*([0-9A-Fa-f]+)\s*\]",
                    addr_part,
                )
                if range_match:
                    lo = int(range_match.group(1), 16)
                    hi = int(range_match.group(2), 16)
                    for a in range(lo, hi + 1):
                        words[a] = data_hex
                else:
                    addr = int(addr_part, 16)
                    words[addr] = data_hex

    if depth == 0:
        depth = max(words.keys()) + 1 if words else 0

    # Build ordered list; fill missing addresses with 0
    hex_digits = (width + 3) // 4
    result = []
    for addr in range(depth):
        val = words.get(addr, "0")
        result.append(val.zfill(hex_digits))

    return result


def write_coe(words: list[str], path: str) -> None:
    """Write Xilinx COE file."""
    with open(path, "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for i, w in enumerate(words):
            sep = "," if i < len(words) - 1 else ";"
            f.write(f"{w}{sep}\n")


def main() -> None:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.mif output.coe", file=sys.stderr)
        sys.exit(1)

    mif_path = sys.argv[1]
    coe_path = sys.argv[2]

    words = parse_mif(mif_path)
    if not words:
        print("ERROR: no data found in MIF file", file=sys.stderr)
        sys.exit(1)

    write_coe(words, coe_path)
    print(f"Converted {len(words)} words: {mif_path} → {coe_path}")


if __name__ == "__main__":
    main()
