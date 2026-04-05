# PicoRV32 FPGA SoC — Quartus / Vivado

A minimal RISC-V System-on-Chip built around the [PicoRV32](https://github.com/YosysHQ/picorv32) soft-core, targeting Intel/Altera Cyclone V (Quartus) with a Vivado port.  
The design integrates on-chip RAM, an I2C master peripheral, and a memory-mapped bus, all written in VHDL, with bare-metal firmware in C/assembly.

---

## Architecture

```
clk_50MHz ──► PLL (÷2) ──► clk_sys 25 MHz
                                │
                         ┌──────▼──────┐
                         │  PicoRV32   │  (RV32IMC Verilog core)
                         └──────┬──────┘
                                │ native memory bus
                         ┌──────▼──────┐
                         │  mem_bus    │  address decoder
                         └──┬──────┬───┘
                            │      │
                    ┌───────▼──┐  ┌▼──────────────┐
                    │onchip_ram│  │i2c_controller  │
                    │ 16 KB    │  │ FSM master     │
                    └──────────┘  └────────────────┘
```

### Memory Map

| Address          | Size  | Module                | Description              |
|------------------|-------|-----------------------|--------------------------|
| `0x0000_0000`    | 16 KB | `onchip_ram.vhd`      | Firmware code + data     |
| `0x1000_0000`    | 16 B  | `i2c_controller.vhd`  | I2C register file        |
| `0x2000_0000`    | 4 B   | GPIO                  | Simple output register   |

### Bus Protocol

PicoRV32 uses a simple valid/ready handshake (not AXI or Wishbone):

```
Cycle 1:  CPU asserts mem_valid, mem_addr, mem_wdata, mem_wstrb
Cycle N:  Slave asserts mem_ready, mem_rdata
```

---

## Repository Structure

```
├── rtl/
│   ├── top_soc.vhd          — Top-level, wires everything together
│   ├── mem_bus.vhd           — Address decoder / memory-mapped bus
│   ├── onchip_ram.vhd        — 16 KB RAM (altsyncram)
│   └── i2c_controller.vhd   — I2C master peripheral (FSM)
├── tb/
│   ├── tb_top_soc.vhd        — Full SoC simulation testbench
│   └── tb_i2c.vhd            — Standalone I2C controller testbench
├── fw/
│   ├── start.S               — RISC-V reset vector (assembly)
│   ├── link.ld               — Linker script
│   ├── main.c                — Bare-metal application
│   ├── i2c_driver.h/.c       — Memory-mapped I2C driver
│   ├── bin2mif.py            — Binary → MIF converter
│   └── Makefile              — Firmware build system
├── docs/
│   └── architecture/         — Per-file design docs
└── vga-vivado-port/          — Vivado port (Artix-7 / Zynq target)
    ├── src/
    ├── constraints/
    ├── ip/
    └── sim/
```

---

## Toolchain

| Tool | Purpose |
|------|---------|
| `riscv64-unknown-elf-gcc` (`-march=rv32imc -mabi=ilp32`) | Firmware compilation |
| `riscv64-unknown-elf-objcopy` | ELF → binary |
| `python3 bin2mif.py` | Binary → MIF (Quartus ROM init) |
| Quartus Prime (Lite) | Synthesis, P&R, ModelSim simulation |
| Vivado | Vivado port synthesis and simulation |

---

## Build

### Firmware (Linux / WSL2)

```bash
cd fw
make          # produces fw.elf, fw.bin, fw.mif
```

Copy `fw.mif` to the Quartus project directory before synthesis so `altsyncram` initialises with the firmware image.

### RTL Simulation (ModelSim via Quartus)

1. Open Quartus project, add all `rtl/` and `tb/` sources.
2. Set `tb_top_soc.vhd` as the top-level simulation entity.
3. Run simulation — the testbench checks that PicoRV32 boots and performs a GPIO write.

For standalone I2C verification use `tb_i2c.vhd`.

### Vivado Port

See [docs/architecture/12_vivado_port.md](docs/architecture/12_vivado_port.md) for target constraints and IP substitutions (`altsyncram` → `block memory generator`).

---

## Clock Domains

| Domain    | Frequency | Source           |
|-----------|-----------|------------------|
| `clk_sys` | 25 MHz    | PLL (÷2 of 50)   |
| `clk_50`  | 50 MHz    | Board oscillator |

I2C SCL divider: `25_000_000 / (2 × 100_000) = 125` counts.

---

## License

MIT
