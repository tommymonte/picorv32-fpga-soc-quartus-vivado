# N-03 — Wrong Last Word Address in MIF Example

**Severity:** Minor
**Status:** OPEN
**Affects:** `fw/bin2mif.py` (documentation only)
**Doc:** [03_onchip_ram.md](../../architecture/03_onchip_ram.md)

---

## Description

The MIF format example in doc 03 shows `3FFF` as the last word address:

```
CONTENT BEGIN
  0000 : 00000093;
  0001 : 00000113;
  ...
  3FFF : 00000000;   -- padding
END;
```

`3FFF` hex = 16383 decimal, which implies 16384 words = 65536 bytes = **64 KB**.

The RAM is 16 KB = 4096 words. The last valid word address is `0FFF` (4095 decimal). This is consistent with:
- `ADDR_WIDTH = 12` in [03_onchip_ram.md](../../architecture/03_onchip_ram.md)
- `DEPTH = 4096` in [11_makefile_bin2mif.md](../../architecture/11_makefile_bin2mif.md)
- `bin2mif.py` which iterates `range(4096)` → addresses `0x000`–`0xFFF`

---

## Fix

```
CONTENT BEGIN
  0000 : 00000093;
  0001 : 00000113;
  ...
  0FFF : 00000000;   -- last word (word address 4095)
END;
```

---

## File to Update

- [03_onchip_ram.md](../../architecture/03_onchip_ram.md) — `.mif File Format` section
