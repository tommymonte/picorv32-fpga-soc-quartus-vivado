# M-01 — Verilog Reduction Syntax in VHDL Port Map

**Severity:** Medium
**Status:** OPEN
**Affects:** `rtl/mem_bus.vhd`
**Doc:** [02_mem_bus.md](../../architecture/02_mem_bus.md)

---

## Description

The I2C controller instantiation in doc 02 uses a Verilog-style reduction OR:

```vhdl
-- WRONG (Verilog syntax)
wen => sel_i2c and mem_valid and (or mem_wstrb),
```

`(or mem_wstrb)` is a Verilog unary reduction operator. It is not valid VHDL in any standard (87, 93, 2008). ModelSim and Quartus will both reject this with a parse error.

---

## Fix

Replace with a VHDL-legal expression that checks whether any byte-enable is set:

```vhdl
-- CORRECT
wen => sel_i2c and mem_valid and (mem_wstrb(3) or mem_wstrb(2) or mem_wstrb(1) or mem_wstrb(0)),
```

Or equivalently:

```vhdl
wen => sel_i2c and mem_valid and to_std_logic(mem_wstrb /= "0000"),
```

(The `to_std_logic` helper from `ieee.std_logic_misc` or a locally defined function.)

The explicit OR chain is preferred — it has no external dependencies and works in VHDL-93.

---

## File to Update

- [02_mem_bus.md](../../architecture/02_mem_bus.md) — I2C Controller Instantiation code block
