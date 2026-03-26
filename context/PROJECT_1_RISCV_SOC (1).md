# Project 1 — PicoRV32 SoC on Intel Cyclone V (with Vivado Port)

## Objective

Design and simulate a minimal RISC-V System-on-Chip on an Intel Cyclone V FPGA, featuring a PicoRV32 softcore processor, on-chip memory, and an I2C peripheral with bare-metal C drivers. Port an existing VGA controller to AMD Vivado to demonstrate cross-toolchain proficiency.

This project directly addresses three skill areas

- RISC-V ISA and FPGA softcores (PicoRV32)
- Hardware/software co-design
- Dual toolchain familiarity (Intel Quartus + AMD Vivado)

---

## Development Environment (No Hardware Required)

This entire project runs on a laptop with no FPGA board. The setup uses a **split Windows + WSL2 workflow**.

### Windows Side (FPGA Toolchains — GUI tools)

| Tool | Version | Purpose | Download |
|------|---------|---------|----------|
| Intel Quartus Prime Lite | 23.1+ | Synthesis, ModelSim simulation | [Intel FPGA Downloads](https://www.intel.com/content/www/us/en/software-kit/download/fpga-design-software.html) (free, no license) |
| AMD Vivado WebPACK | 2024.1+ | Vivado port (Part B) | [AMD Downloads](https://www.xilinx.com/support/download.html) (free for Artix-7) |

> **Why Windows?** Quartus and Vivado have stable Windows installers with native GUI performance. Running them under WSL2 requires X11/Wayland forwarding and is fragile — not worth the effort.

### WSL2 Side (Ubuntu 24.04 — firmware toolchain, scripting, Git)

```bash
# Install WSL2 if not already present (PowerShell as Admin)
wsl --install -d Ubuntu-24.04

# Inside WSL2: install RISC-V toolchain and utilities
sudo apt update && sudo apt install -y \
  gcc-riscv64-unknown-elf \
  binutils-riscv64-unknown-elf \
  make cmake git python3 python3-pip \
  gtkwave

# Verify
riscv64-unknown-elf-gcc --version
```

> **Note:** The `riscv64-unknown-elf-gcc` package supports RV32 targets via `-march=rv32imc -mabi=ilp32`. If your distro doesn't ship it, build from source or use the [SiFive prebuilt toolchain](https://github.com/sifive/freedom-tools/releases).

### Cross-Environment Workflow

```
┌─────────────────────────────────────────────────────────┐
│  VS Code (Remote - WSL extension)                       │
│  Single editor for both environments                    │
├─────────────────────┬───────────────────────────────────┤
│  WSL2 (Ubuntu)      │  Windows                          │
│                     │                                   │
│  • Edit VHDL/C      │  • Quartus project (synthesis)    │
│  • Compile firmware  │  • ModelSim (simulation)          │
│  • Generate .mif     │  • Vivado (Part B)                │
│  • Git operations    │                                   │
│  • Scripts/Makefile  │                                   │
├─────────────────────┴───────────────────────────────────┤
│  Shared filesystem:                                     │
│  WSL2 → /mnt/c/Users/<you>/quartus_projects/            │
│  Windows → \\wsl$\Ubuntu-24.04\home\<you>\fw\           │
└─────────────────────────────────────────────────────────┘
```

**Recommended project layout:**
- Keep the **Quartus project** on the Windows filesystem (`C:\projects\picorv32-soc\`) so Quartus can access it natively.
- Keep the **firmware source and build** in WSL2 (`~/fw/picorv32-soc/`).
- Use a simple `Makefile` in WSL2 that compiles firmware and copies the resulting `.mif` file to the Windows Quartus project folder:
  ```makefile
  QUARTUS_DIR := /mnt/c/projects/picorv32-soc

  fw.mif: fw.bin
  	python3 bin2mif.py fw.bin fw.mif
  	cp fw.mif $(QUARTUS_DIR)/fw.mif

  fw.bin: fw.elf
  	riscv64-unknown-elf-objcopy -O binary fw.elf fw.bin

  fw.elf: start.S main.c i2c_driver.c
  	riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 \
  	  -nostdlib -T link.ld -o fw.elf start.S main.c i2c_driver.c
  ```

---

## Part A — RISC-V SoC (Days 1–5)

### Architecture

```
┌─────────────────────────────────────────────────┐
│                 Top-Level (VHDL)                 │
│                                                  │
│  ┌────────────┐    ┌─────────────────────────┐   │
│  │  PicoRV32  │    │     Memory Bus (VHDL)    │   │
│  │  (Verilog) │◄──►│                         │   │
│  │            │    │  0x0000_0000  On-Chip RAM│   │
│  │  RISC-V    │    │  0x1000_0000  I2C Periph │   │
│  │  RV32IMC   │    │  0x2000_0000  GPIO (opt) │   │
│  └────────────┘    └─────────────────────────┘   │
│                                                  │
│  ┌────────────┐    ┌─────────────────────────┐   │
│  │    PLL     │    │   I2C Controller (VHDL)  │   │
│  │ 50→25 MHz  │    │   - Start/Stop           │   │
│  └────────────┘    │   - Byte TX/RX + ACK     │   │
│                    │   - SCL/SDA open-drain    │   │
│                    └─────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Memory Map

| Base Address   | Size   | Peripheral           | Access |
|----------------|--------|----------------------|--------|
| `0x0000_0000`  | 16 KB  | On-chip RAM (firmware)| R/W   |
| `0x1000_0000`  | 16 B   | I2C Controller        | R/W   |
| `0x2000_0000`  | 4 B    | GPIO (optional)       | R/W   |

### I2C Register Map

| Offset | Register    | Bits  | Description                                |
|--------|-------------|-------|--------------------------------------------|
| `0x00` | CTRL        | [7:0] | [0] EN, [1] START, [2] STOP, [3] RW       |
| `0x04` | STATUS      | [7:0] | [0] BUSY, [1] ACK_RECV, [2] ERROR         |
| `0x08` | TX_DATA     | [7:0] | Byte to transmit                           |
| `0x0C` | RX_DATA     | [7:0] | Last received byte                         |

### Day-by-Day Plan

#### Day 1 — Setup & Architecture Definition

**Goal:** Working toolchain, clear architecture, initial repo.

Tasks:
1. **Windows:** Install Intel Quartus Prime Lite + ModelSim (if not already installed).
2. **WSL2:** Install RISC-V GCC toolchain (see Development Environment section above).
3. **WSL2:** Clone PicoRV32 from `https://github.com/YosysHQ/picorv32`.
4. Study `picorv32.v` interface: `mem_valid`, `mem_ready`, `mem_addr`, `mem_wdata`, `mem_rdata`.
5. **WSL2:** Create GitHub repo `picorv32-soc-cyclone-v`, push initial architecture docs.
6. Write `docs/architecture.md` with block diagram and memory map (tables above).
7. **Windows:** Create Quartus project targeting Cyclone V (5CSXFC6D6F31C6 or any available in Lite) in `C:\projects\picorv32-soc\`.
8. **WSL2:** Verify cross-compilation works: `riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -x c -c /dev/null -o /dev/null`

**Deliverables:** Repo with architecture docs, empty Quartus project, both toolchains verified (Quartus on Windows, RISC-V GCC on WSL2).

#### Day 2 — Core Instantiation & On-Chip Memory

**Goal:** PicoRV32 boots and executes from on-chip RAM.

Tasks:
1. **Windows/Quartus:** Write `rtl/top_soc.vhd` — VHDL top-level that instantiates PicoRV32 (Quartus mixed-language support).
2. **Windows/Quartus:** Implement `rtl/mem_bus.vhd` — address decoder that routes bus transactions by address range.
3. **Windows/Quartus:** Implement `rtl/onchip_ram.vhd` — 16 KB RAM using `altsyncram` megafunction, initialized from `.mif` file.
4. **WSL2:** Write minimal firmware in `fw/main.c`:
   ```c
   #define GPIO_BASE 0x20000000
   volatile unsigned int *gpio = (volatile unsigned int *)GPIO_BASE;

   void main(void) {
       int counter = 0;
       while (1) {
           *gpio = counter++;
       }
   }
   ```
5. **WSL2:** Write `fw/start.S` (startup assembly: set stack pointer, jump to `main`).
6. **WSL2:** Write `fw/link.ld` (linker script mapping `.text` to `0x0000_0000`).
7. **WSL2:** Cross-compile and generate .mif:
   ```bash
   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -T link.ld -o fw.elf start.S main.c
   riscv64-unknown-elf-objcopy -O binary fw.elf fw.bin
   python3 bin2mif.py fw.bin fw.mif
   cp fw.mif /mnt/c/projects/picorv32-soc/fw.mif
   ```
8. **Windows/Quartus:** Run synthesis (doesn't need to fully close timing — just verify elaboration).

**Deliverables:** Synthesizable top-level with PicoRV32 + RAM, compiled firmware, `.mif` file.

#### Day 3 — Simulation & Debug

**Goal:** See PicoRV32 executing firmware in ModelSim waveforms.

Tasks:
1. **Windows/ModelSim:** Write `tb/tb_top_soc.vhd` — testbench that instantiates `top_soc`, provides clock (50 MHz) and reset.
2. **Windows/ModelSim:** Load firmware `.mif` into RAM in simulation.
3. **Windows/ModelSim:** Run ModelSim simulation for ~10,000 clock cycles.
4. Verify in waveform viewer:
   - `mem_valid` asserts with correct `mem_addr` values (instruction fetches from `0x0000_xxxx`).
   - After executing the loop, `mem_addr` hits `0x2000_0000` (GPIO write).
   - `mem_wdata` shows incrementing counter values.
5. Debug issues (common problems: endianness of `.mif`, reset timing, `mem_ready` handshake).
6. Take waveform screenshots for documentation.

**Deliverables:** Working simulation, waveform screenshots in `docs/`, passing testbench.

#### Day 4 — I2C Peripheral in VHDL

**Goal:** Standalone, verified I2C controller.

Tasks:
1. Write `rtl/i2c_controller.vhd`:
   - Bus interface: `addr`, `wdata`, `rdata`, `wen`, `ren`, `ready`.
   - I2C FSM: IDLE → START → ADDR → ACK_WAIT → DATA → ACK → STOP.
   - SCL generation from system clock (divide to ~100 kHz).
   - SDA open-drain modeling (directly drive directly in simulation; tristate in synthesis).
2. Write `tb/tb_i2c.vhd`:
   - Instantiate I2C controller.
   - Simulate a write transaction: write slave address + data byte.
   - Model a simple I2C slave that ACKs every byte (pull SDA low on 9th clock).
   - Verify SCL/SDA waveforms match I2C protocol timing.
3. Run ModelSim, capture I2C bus waveforms showing START, address, ACK, data, STOP.

**Deliverables:** `i2c_controller.vhd`, testbench, waveform showing valid I2C transaction.

#### Day 5 — Integration & Bare-Metal Driver

**Goal:** Full SoC running firmware that talks to I2C peripheral.

Tasks:
1. Connect `i2c_controller` to `mem_bus` at address `0x1000_0000`.
2. Write `fw/i2c_driver.h` and `fw/i2c_driver.c`:
   ```c
   #define I2C_BASE    0x10000000
   #define I2C_CTRL    (*(volatile uint32_t *)(I2C_BASE + 0x00))
   #define I2C_STATUS  (*(volatile uint32_t *)(I2C_BASE + 0x04))
   #define I2C_TX_DATA (*(volatile uint32_t *)(I2C_BASE + 0x08))
   #define I2C_RX_DATA (*(volatile uint32_t *)(I2C_BASE + 0x0C))

   void i2c_init(void);
   int  i2c_write_byte(uint8_t slave_addr, uint8_t data);
   int  i2c_read_byte(uint8_t slave_addr, uint8_t *data);
   ```
3. Update `fw/main.c` to call `i2c_write_byte()` on boot.
4. Recompile firmware, update `.mif`, re-run full SoC simulation.
5. Verify in waveform: firmware boots → writes to I2C registers → I2C controller drives SCL/SDA.
6. Write final README section with full build instructions.

**Deliverables:** Complete SoC with CPU + memory + I2C, integrated firmware, full simulation, documentation.

---

## Part B — Vivado Port of VGA Controller (Day 6)

### Objective

Port the existing VGA 640×480 controller from Intel Quartus to AMD Vivado, demonstrating cross-toolchain FPGA development.

### Target Device

Xilinx Artix-7 `xc7a35tcpg236-1` (supported by free Vivado WebPACK).

### Porting Checklist

| Component              | Quartus (Original)            | Vivado (Ported)                     |
|------------------------|-------------------------------|-------------------------------------|
| Constraint file        | `.sdc`                        | `.xdc` (Xilinx Design Constraints) |
| PLL / Clock            | Altera PLL megafunction       | Clocking Wizard IP (MMCM)          |
| Block RAM              | `altsyncram` IP               | Block Memory Generator IP          |
| Pin assignments        | Quartus Pin Planner           | XDC `set_property PACKAGE_PIN`     |
| Simulation             | ModelSim (Altera Edition)     | Vivado Simulator (xsim)            |

### Tasks

1. **Windows:** Install AMD Vivado WebPACK if not already present (free, ~40 GB disk space).
2. **Windows/Vivado:** Create a new Vivado project targeting Artix-7 (`xc7a35tcpg236-1`).
3. Import VHDL source files (no changes needed to core logic).
4. **Windows/Vivado:** Replace Altera PLL with Clocking Wizard IP (50 MHz → 25 MHz) via IP Integrator.
5. **Windows/Vivado:** Replace `altsyncram` with Block Memory Generator IP, import same `.mif` data (may need `.coe` format conversion — use a small Python script in WSL2).
6. **Windows/Vivado:** Write `.xdc` constraint file with clock constraint and (dummy) pin assignments.
7. **Windows/Vivado:** Run Synthesis → capture utilization report (screenshot).
8. **Windows/Vivado:** Run Implementation → capture timing report (screenshot).
9. **Windows/Vivado:** Run Behavioral Simulation in xsim → verify VGA timing waveforms match ModelSim results.
10. Write `PORTING_NOTES.md` documenting every difference encountered.

### Expected Deliverables

```
vga-controller-vivado-port/
├── README.md
├── PORTING_NOTES.md
├── src/
│   ├── vga_controller.vhd
│   ├── top.vhd
│   └── rom_image.vhd
├── constraints/
│   └── artix7.xdc
├── ip/
│   └── (Clocking Wizard + BRAM config)
├── sim/
│   └── tb_vga.vhd
├── docs/
│   ├── utilization_report.png
│   ├── timing_report.png
│   └── waveform_comparison.png
└── quartus_original/
    └── (link or reference to original project)
```

---

## Day 7 — Documentation & Polish

### Tasks

1. Write comprehensive `README.md` for both repos:
   - Project overview and motivation.
   - Architecture block diagram.
   - Build instructions (step-by-step, from clean clone).
   - Simulation instructions with expected output.
   - Screenshots of key waveforms.
2. Add `LICENSE` file (MIT or similar).
3. Verify that a clean clone + follow the instructions actually works.
4. Create a `docs/` folder with all diagrams and screenshots.
5. Clean up commit history: squash WIP commits, write meaningful messages.

---

## Skills Demonstrated (mapped to CERN requirements)

| CERN Requirement                        | Evidence in This Project                              |
|-----------------------------------------|-------------------------------------------------------|
| FPGA gateware development               | Full SoC design in VHDL, synthesis in Quartus         |
| RISC-V ISA                              | PicoRV32 instantiation, firmware, linker scripts      |
| FPGA softcores (PicoRV32)               | Direct instantiation and integration                  |
| Hardware/software co-design             | Memory-mapped peripheral + bare-metal C driver        |
| C for embedded applications             | Bare-metal firmware, register-level peripheral access |
| Intel Quartus                           | Full synthesis flow, ModelSim simulation               |
| AMD Vivado                              | VGA controller port, synthesis + simulation            |
| Communication interfaces (I2C)          | Custom I2C controller in VHDL + C driver              |
| VHDL 2008                               | All RTL and testbenches in VHDL 2008                  |
| Functional verification                 | ModelSim testbenches, waveform validation              |
