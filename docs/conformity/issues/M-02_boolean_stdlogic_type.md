# M-02 — Boolean Result ANDed with std_logic

**Severity:** Medium
**Status:** OPEN
**Affects:** `rtl/mem_bus.vhd`
**Doc:** [02_mem_bus.md](../../architecture/02_mem_bus.md)

---

## Description

The `ren` port in the I2C instantiation uses a comparison whose result is `boolean`, then ANDs it with `std_logic` signals:

```vhdl
-- WRONG — type mismatch
ren => sel_i2c and mem_valid and (mem_wstrb = "0000"),
```

In VHDL, `(mem_wstrb = "0000")` returns `boolean`. The `and` operator cannot mix `boolean` and `std_logic` — they are distinct types. This causes a compilation error under VHDL-93 and VHDL-2008.

---

## Fix

Express the condition entirely in `std_logic`:

```vhdl
-- CORRECT
ren => sel_i2c and mem_valid and not (mem_wstrb(3) or mem_wstrb(2) or mem_wstrb(1) or mem_wstrb(0)),
```

This is equivalent to: `mem_wstrb = "0000"` but returns `std_logic`.

---

## File to Update

- [02_mem_bus.md](../../architecture/02_mem_bus.md) — I2C Controller Instantiation code block
