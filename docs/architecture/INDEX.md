# Architecture Documentation Index

This folder contains implementation architecture guides for every file in the PicoRV32 SoC project.

## Reading Order (matches Day-by-Day implementation plan)

| File | Implements | Day |
|------|-----------|-----|
| [00_overview.md](00_overview.md) | Full system architecture, memory map, bus protocol, build flow | Day 1 |
| [08_link_ld.md](08_link_ld.md) | `fw/link.ld` — memory layout for firmware | Day 2 |
| [07_start_S.md](07_start_S.md) | `fw/start.S` — RISC-V reset vector and stack init | Day 2 |
| [09_main_c.md](09_main_c.md) | `fw/main.c` — firmware application (GPIO + I2C) | Day 2/5 |
| [11_makefile_bin2mif.md](11_makefile_bin2mif.md) | `fw/Makefile` + `fw/bin2mif.py` — build pipeline | Day 2 |
| [03_onchip_ram.md](03_onchip_ram.md) | `rtl/onchip_ram.vhd` — 16 KB altsyncram | Day 2 |
| [02_mem_bus.md](02_mem_bus.md) | `rtl/mem_bus.vhd` — address decoder and bus mux | Day 2 |
| [01_top_soc.md](01_top_soc.md) | `rtl/top_soc.vhd` — top-level wiring | Day 2 |
| [05_tb_top_soc.md](05_tb_top_soc.md) | `tb/tb_top_soc.vhd` — full SoC simulation | Day 3 |
| [04_i2c_controller.md](04_i2c_controller.md) | `rtl/i2c_controller.vhd` — I2C master FSM | Day 4 |
| [06_tb_i2c.md](06_tb_i2c.md) | `tb/tb_i2c.vhd` — I2C controller testbench | Day 4 |
| [10_i2c_driver.md](10_i2c_driver.md) | `fw/i2c_driver.h` + `fw/i2c_driver.c` — bare-metal driver | Day 5 |
| [12_vivado_port.md](12_vivado_port.md) | VGA controller Vivado port (all Part B files) | Day 6 |
