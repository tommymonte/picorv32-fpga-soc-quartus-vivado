# PicoRV32 SoC — System Architecture Overview

## Purpose

This document is the master reference for the full SoC implementation. It describes the complete system, the relationships between every file you must write, and the data flow through the hardware and firmware layers.

---

## Repository Structure

```
picorv32-soc-cyclone-v/
├── rtl/
│   ├── top_soc.vhd          ← VHDL top-level, wires everything together
│   ├── mem_bus.vhd          ← Address decoder / memory-mapped bus
│   ├── onchip_ram.vhd       ← 16 KB RAM (altsyncram)
│   └── i2c_controller.vhd  ← I2C master peripheral
├── tb/
│   ├── tb_top_soc.vhd       ← Full SoC simulation testbench
│   └── tb_i2c.vhd           ← Standalone I2C controller testbench
├── fw/
│   ├── start.S              ← RISC-V startup code (assembly)
│   ├── link.ld              ← Linker script
│   ├── main.c               ← Main firmware application
│   ├── i2c_driver.h         ← I2C bare-metal driver interface
│   ├── i2c_driver.c         ← I2C bare-metal driver implementation
│   ├── bin2mif.py           ← Binary → MIF converter tool
│   └── Makefile             ← Build system
├── docs/
│   └── architecture/        ← This folder
└── vga-vivado-port/         ← Part B: Vivado port (separate project)
    ├── src/
    ├── constraints/
    ├── ip/
    └── sim/
```

---

## Block Diagram

```
                        ┌──────────────────────────────────────────────────┐
                        │                top_soc.vhd                       │
                        │                                                  │
  clk_50mhz ──────────►│  ┌─────────┐   ┌──────────────────────────────┐  │
  reset_n   ──────────►│  │   PLL   │   │        PicoRV32 (Verilog)    │  │
                        │  │ 50→25MHz│──►│  mem_valid  mem_ready        │  │
                        │  └─────────┘   │  mem_addr   mem_rdata        │  │
                        │                │  mem_wdata  mem_wstrb        │  │
                        │                └──────────┬───────────────────┘  │
                        │                           │  Memory Bus          │
                        │                ┌──────────▼───────────────────┐  │
                        │                │       mem_bus.vhd             │  │
                        │                │   Address Decoder             │  │
                        │                │  0x0000_0000 → RAM            │  │
                        │                │  0x1000_0000 → I2C            │  │
                        │                │  0x2000_0000 → GPIO           │  │
                        │                └───┬────────────┬──────────────┘  │
                        │                    │            │                  │
                        │         ┌──────────▼──┐   ┌────▼─────────────┐   │
                        │         │onchip_ram   │   │i2c_controller    │   │
                        │         │.vhd 16 KB   │   │.vhd              │   │
                        │         │altsyncram   │   │SCL/SDA outputs   │   │
                        │         └─────────────┘   └──────────────────┘   │
                        └──────────────────────────────────────────────────┘

  Firmware (compiled by riscv64-unknown-elf-gcc, loaded as .mif into RAM):
  ┌─────────────────────────────────────────────────────────────────┐
  │  start.S → sets sp, jumps to main                               │
  │  main.c  → calls i2c_write_byte(), writes GPIO counter         │
  │  i2c_driver.c → memory-mapped register writes to I2C periph    │
  └─────────────────────────────────────────────────────────────────┘
```

---

## Memory Map

| Base Address   | Size  | Module            | Description               |
|----------------|-------|-------------------|---------------------------|
| `0x0000_0000`  | 16 KB | `onchip_ram.vhd`  | Firmware code + data      |
| `0x1000_0000`  | 16 B  | `i2c_controller.vhd` | I2C register file      |
| `0x2000_0000`  | 4 B   | GPIO (optional)   | Simple output register    |

---

## PicoRV32 Bus Protocol

PicoRV32 uses a simple native memory bus (not AXI or Wishbone by default). Every slave must implement this handshake:

```
Cycle 1:  CPU asserts mem_valid=1, mem_addr, mem_wdata, mem_wstrb
Cycle N:  Slave asserts mem_ready=1, mem_rdata (for reads)
          → CPU latches rdata, deasserts mem_valid
```

- `mem_valid`: CPU has a pending transaction.
- `mem_ready`: Slave accepted the transaction (single-cycle or multi-cycle).
- `mem_wstrb[3:0]`: Byte-enable mask. `0000` = read, `1111` = 32-bit write, etc.
- `mem_rdata[31:0]`: Read data (only valid when `mem_ready=1` on a read).

**Single-cycle RAM** can tie `mem_ready` high combinatorially.
**I2C controller** can also respond in one cycle (register read/write is instant; the actual I2C protocol runs independently via FSM).

---

## Clock Domain

| Domain     | Frequency | Source          | Used by                    |
|------------|-----------|-----------------|----------------------------|
| `clk_sys`  | 25 MHz    | PLL (÷2 of 50)  | PicoRV32, RAM, I2C periph  |
| `clk_50`   | 50 MHz    | Board oscillator| PLL input only             |

> The I2C SCL divider inside `i2c_controller.vhd` must divide `clk_sys` (25 MHz) down to 100 kHz. Divider ratio = 25,000,000 / (2 × 100,000) = 125.

---

## Build Flow

```
WSL2:
  start.S + main.c + i2c_driver.c
       │
       ▼ riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -T link.ld
  fw.elf
       │
       ▼ riscv64-unknown-elf-objcopy -O binary
  fw.bin
       │
       ▼ python3 bin2mif.py fw.bin fw.mif
  fw.mif  ──── cp ──►  C:\projects\picorv32-soc\fw.mif

Quartus (Windows):
  top_soc.vhd + mem_bus.vhd + onchip_ram.vhd + i2c_controller.vhd + fw.mif
       │
       ▼ Synthesis + (optional) Simulation via ModelSim
  Netlist / Simulation results
```

---

## File Implementation Order

Implement in this order to allow incremental testing:

1. `fw/link.ld` — defines memory layout (no dependencies)
2. `fw/start.S` — minimal reset vector (depends on link.ld)
3. `fw/main.c` — trivial GPIO loop first (no I2C yet)
4. `fw/bin2mif.py` — needed to load firmware into Quartus
5. `fw/Makefile` — ties steps 1–4 together
6. `rtl/onchip_ram.vhd` — RAM with altsyncram (standalone)
7. `rtl/mem_bus.vhd` — address decoder (depends on RAM interface)
8. `rtl/top_soc.vhd` — top-level wiring (depends on mem_bus, PicoRV32)
9. `tb/tb_top_soc.vhd` — simulate the basic boot (no I2C yet)
10. `rtl/i2c_controller.vhd` — I2C FSM (standalone)
11. `tb/tb_i2c.vhd` — verify I2C protocol in isolation
12. `fw/i2c_driver.h` + `fw/i2c_driver.c` — software side
13. Integrate: update `mem_bus.vhd` to add I2C, rerun full simulation
