# M-03 — Computed Expression in Port Map (Quartus VHDL-93)

**Severity:** Medium
**Status:** OPEN
**Affects:** `rtl/top_soc.vhd`
**Doc:** [01_top_soc.md](../../architecture/01_top_soc.md)

---

## Description

The PicoRV32 instantiation maps an inline `not` expression directly in the port map:

```vhdl
-- Potentially invalid in Quartus VHDL-93
resetn => not rst,
```

VHDL-93 does not allow arbitrary expressions in port map associations — only names and conversions are permitted. Quartus historically enforces this restriction and will report:

```
Error: VHDL expression is not supported in this context
```

VHDL-2008 relaxes this rule, but Quartus support for VHDL-2008 expressions in port maps is inconsistent across versions.

---

## Fix

Declare an explicit intermediate signal in the `architecture` declaration section:

```vhdl
signal cpu_resetn : std_logic;
```

Drive it with a concurrent statement:

```vhdl
cpu_resetn <= not rst;
```

Then map it:

```vhdl
resetn => cpu_resetn,
```

This is unambiguous in all VHDL standards and all Quartus versions.

---

## File to Update

- [01_top_soc.md](../../architecture/01_top_soc.md) — Internal Signals section and PicoRV32 instantiation block
