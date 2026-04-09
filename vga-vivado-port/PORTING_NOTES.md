# PORTING_NOTES.md — VGA Controller: Quartus/Cyclone V → Vivado/Artix-7

## Objective

Port an existing VGA 640×480 @ 60 Hz controller from Intel Quartus Prime
(Cyclone V target) to AMD Vivado (Artix-7 target), demonstrating cross-toolchain
FPGA proficiency. The core VHDL logic (`vga_controller.vhd`) is **unchanged**;
only vendor-specific IP and constraint files change.

---

## Differences Found

| Category | Quartus / Cyclone V | Vivado / Artix-7 | Notes |
|---|---|---|---|
| **Clock IP** | `ALTPLL` megafunction, generates a `.vhd` wrapper | Clocking Wizard IP (`clk_wiz_0`), generates `.xci` + wrapper | Parameter names differ; Vivado wizard uses `clk_in1`/`clk_out1` vs `inclk0`/`c0` |
| **ROM/RAM IP** | `altsyncram` megafunction (direct VHDL instantiation) | Block Memory Generator (`blk_mem_gen_0`), generates `.xci` + wrapper | Init file format changes: `.mif` → `.coe` (see `tools/mif2coe.py`) |
| **Constraints** | `.sdc` (Synopsys Design Constraints, Tcl-based) | `.xdc` (Xilinx Design Constraints, Tcl-based) | Similar `create_clock` syntax, but I/O standards use `set_property IOSTANDARD` instead of `set_location_assignment` |
| **Pin assignments** | Quartus Pin Planner or `.qsf` `set_location_assignment` | `.xdc` `set_property PACKAGE_PIN` | Direct equivalent, different syntax |
| **Simulation** | ModelSim with `.do` scripts | Vivado built-in `xsim` with `.tcl` scripts | Both support TCL but different APIs; `std.env.stop` terminates xsim cleanly |
| **Top-level IP port names** | `inclk0`, `c0`, `locked` (ALTPLL) | `clk_in1`, `clk_out1`, `locked` (Clocking Wizard) | Must update top-level port map |
| **Synthesis reports** | Timing Analyzer (Fmax, slack columns) | Implementation Report (WNS = Worst Negative Slack) | Equivalent concept, different UI and report format |
| **IP generation** | MegaWizard Plug-In Manager | IP Catalog (Tools → Create IP) | Both GUI-driven; Vivado also supports Tcl (`create_ip`) for scripted flows |

---

## Step-by-Step Porting Process

### 1. Copy core logic unchanged

`src/vga_controller.vhd` is imported directly from the Quartus project.
No edits to timing counters, sync generation, or RGB output logic.

### 2. Replace top-level

`src/top.vhd` replaces the Quartus top.
- `ALTPLL` instantiation replaced with `clk_wiz_0` component.
- `altsyncram` ROM removed (test pattern generated from counters; for pixel ROM
  replace with `blk_mem_gen_0` — see note below).
- Reset logic unchanged in function: hold until PLL locked.

### 3. Generate Clocking Wizard

In Vivado GUI:
1. Tools → Create IP → Clocking Wizard → `clk_wiz_0`
2. Input frequency: 100 MHz
3. Output CLK_OUT1: 25 MHz
4. Device: xc7a35tcpg236-1
5. Generate and add `.xci` to project sources.

### 4. Convert MIF to COE (if ROM used)

```
python3 tools/mif2coe.py  ../fw/fw.mif  pixel_rom.coe
```

Load `pixel_rom.coe` in the Block Memory Generator IP wizard.

### 5. Add constraints

Add `constraints/artix7.xdc` to the Vivado project.
**Verify pin assignments against your actual board schematic** — the assignments
in the file target a Basys3. Other Artix-7 boards will have different pin names.

### 6. Simulate with xsim

```
# In Vivado Tcl console or launch from Flow menu:
launch_simulation
run all
```

The testbench (`sim/tb_vga.vhd`) uses `std.env.stop` to halt simulation.
For ModelSim compatibility remove that line and use `wait;` instead.

### 7. Synthesise and implement

```
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

---

## Known Differences Not Affecting Functionality

- Vivado infers block RAM for large arrays even without explicit IP; `altsyncram`
  has no direct Vivado equivalent but is unnecessary.
- Quartus Fmax reports are per-path; Vivado reports WNS globally. Both designs
  should close timing at 25 MHz with substantial margin on Artix-7.
- Vivado simulation requires the Xilinx simulation library (`unisim`) for any
  primitive instantiation; this design uses no device primitives directly so no
  extra library is needed beyond IEEE.

---

## Files Summary

```
vga-vivado-port/
├── src/
│   ├── vga_controller.vhd   ← Ported unchanged from Quartus project
│   └── top.vhd              ← Vivado-specific top (Clocking Wizard, no altsyncram)
├── constraints/
│   └── artix7.xdc           ← Replaces .sdc; Basys3 pin assignments
├── sim/
│   └── tb_vga.vhd           ← Behavioral testbench (xsim + ModelSim compatible)
├── tools/
│   └── mif2coe.py           ← Converts Intel .mif → Xilinx .coe
└── PORTING_NOTES.md         ← This file
```
