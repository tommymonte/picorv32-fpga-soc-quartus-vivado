# N-01 — Wrong Bit-Width in RAM Address Comment

**Severity:** Minor
**Status:** OPEN
**Affects:** `rtl/mem_bus.vhd` (documentation only)
**Doc:** [02_mem_bus.md](../../architecture/02_mem_bus.md)

---

## Description

The RAM instantiation comment states "14-bit → 16K words":

```vhdl
addr => mem_addr(13 downto 2),   -- word address: 14-bit → 16K words
```

`mem_addr(13 downto 2)` spans bits 13 down to 2 inclusive = **12 bits**.
2¹² = 4096 words × 4 bytes = 16 KB. The RAM is 16 KB, not 64 KB.

"14-bit → 16K words" implies 2¹⁴ = 16384 words = 64 KB — both figures are wrong.

---

## Fix

```vhdl
addr => mem_addr(13 downto 2),   -- 12-bit word address → 4K words (16 KB)
```

---

## File to Update

- [02_mem_bus.md](../../architecture/02_mem_bus.md) — On-Chip RAM Instantiation code block
