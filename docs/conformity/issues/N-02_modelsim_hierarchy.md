# N-02 — Wrong ModelSim Signal Hierarchy Paths

**Severity:** Minor
**Status:** OPEN
**Affects:** `tb/tb_top_soc.vhd` (documentation only)
**Doc:** [05_tb_top_soc.md](../../architecture/05_tb_top_soc.md)

---

## Description

The waveform observation table references signal paths with `u_cpu` nested inside `u_mem_bus`:

```
u_dut/u_mem_bus/u_cpu/mem_valid
u_dut/u_mem_bus/u_cpu/mem_addr
u_dut/u_mem_bus/u_cpu/mem_wstrb
```

This is wrong. Per [01_top_soc.md](../../architecture/01_top_soc.md), `u_cpu` (PicoRV32) is instantiated directly inside `top_soc`, not inside `mem_bus`. The memory bus signals (`mem_valid`, `mem_addr`, etc.) are declared as signals at the `top_soc` level.

Correct hierarchy:
```
tb_top_soc
└── u_dut  (top_soc)
    ├── u_cpu        (picorv32)
    └── u_mem_bus    (mem_bus)
        ├── u_ram    (onchip_ram)
        └── u_i2c    (i2c_controller)
```

---

## Fix

Replace the incorrect paths in the "What to Observe in Waveforms" table:

| Wrong path | Correct path |
|------------|--------------|
| `u_dut/u_mem_bus/u_cpu/mem_valid` | `/tb_top_soc/u_dut/mem_valid` |
| `u_dut/u_mem_bus/u_cpu/mem_addr` | `/tb_top_soc/u_dut/mem_addr` |
| `u_dut/u_mem_bus/u_cpu/mem_wstrb` | `/tb_top_soc/u_dut/mem_wstrb` |

These are signals at the `top_soc` architecture level and are visible at the `u_dut` scope in ModelSim.

Also update the TCL `add wave` commands in the simulation script — the hex references are already written as `/tb_top_soc/u_dut/mem_valid` etc., which is correct. Only the prose table needs fixing.

---

## File to Update

- [05_tb_top_soc.md](../../architecture/05_tb_top_soc.md) — "What to Observe in Waveforms" table
