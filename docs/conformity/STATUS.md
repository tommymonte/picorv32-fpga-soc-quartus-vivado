# Architecture Conformity Status

Reviewed: 2026-04-05
Scope: all files under `docs/architecture/`
Reviewer: automated cross-reference pass

## Issue Tracker

| ID | Severity | Source doc(s) | Title | Status |
|----|----------|---------------|-------|--------|
| [C-01](issues/C-01_fsm_driver_mismatch.md) | Critical | 04, 10 | FSM/driver protocol mismatch — BUSY polling model incompatible with FSM | OPEN |
| [M-01](issues/M-01_vhdl_reduction_syntax.md) | Medium | 02 | Verilog reduction `(or mem_wstrb)` used in VHDL port map | OPEN |
| [M-02](issues/M-02_boolean_stdlogic_type.md) | Medium | 02 | Boolean result of `(mem_wstrb = "0000")` ANDed with `std_logic` | OPEN |
| [M-03](issues/M-03_portmap_expression.md) | Medium | 01 | `not rst` expression in port map — invalid in Quartus VHDL-93 | OPEN |
| [N-01](issues/N-01_ram_addr_comment.md) | Minor | 02 | Comment says "14-bit → 16K words" — slice is 12-bit → 4K words | OPEN |
| [N-02](issues/N-02_modelsim_hierarchy.md) | Minor | 05 | ModelSim signal paths place `u_cpu` inside `u_mem_bus` — wrong hierarchy | OPEN |
| [N-03](issues/N-03_mif_last_address.md) | Minor | 03 | MIF example shows last word `3FFF` — should be `0FFF` for 4096-word RAM | OPEN |
| [N-04](issues/N-04_missing_ram_addr_signal.md) | Minor | 02 | `ram_addr` used in code snippet but absent from Internal Signal Summary | OPEN |

## Severity Legend

| Level | Meaning |
|-------|---------|
| Critical | Would produce wrong hardware behavior or infinite hang at runtime |
| Medium | Would fail to compile or simulate as written |
| Minor | Documentation inaccuracy — no runtime impact but misleads implementer |

## Overall Status

**NOT CONFORMANT** — 1 critical issue and 3 medium issues must be resolved before implementation begins.
