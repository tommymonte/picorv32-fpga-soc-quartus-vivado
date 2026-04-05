# N-04 — `ram_addr` Missing from Internal Signal Summary

**Severity:** Minor
**Status:** OPEN
**Affects:** `rtl/mem_bus.vhd` (documentation only)
**Doc:** [02_mem_bus.md](../../architecture/02_mem_bus.md)

---

## Description

The code snippet in doc 02 declares and uses `ram_addr`:

```vhdl
-- Address: strip byte-address bits [1:0] and range-select bits [31:14]
ram_addr <= mem_addr(13 downto 2);

u_ram : entity work.onchip_ram
    port map (
        addr  => ram_addr,
        ...
    );
```

However, `ram_addr` is not listed in the Internal Signal Summary table:

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `sel_ram` | 1 | internal | ... |
| `sel_i2c` | 1 | internal | ... |
| `sel_gpio` | 1 | internal | ... |
| `ram_rdata` | 32 | internal | ... |
| `ram_ready` | 1 | internal | ... |
| `i2c_rdata` | 32 | internal | ... |
| `i2c_ready` | 1 | internal | ... |
| `gpio_reg` | 32 | internal | ... |

`ram_addr` is absent.

---

## Fix

Add the missing row to the Internal Signal Summary table:

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `ram_addr` | 12 | internal | Word address for RAM — `mem_addr[13:2]` |

---

## File to Update

- [02_mem_bus.md](../../architecture/02_mem_bus.md) — Internal Signal Summary table
