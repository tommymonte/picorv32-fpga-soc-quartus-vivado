# `tb/tb_top_soc.vhd` — Top-Level SoC Testbench

## Role in the System

This is the **ModelSim simulation entry point** for the full SoC. It drives clocks and resets into `top_soc`, loads firmware via the `.mif` file (already embedded in `onchip_ram`), and lets you observe the waveforms to verify correct CPU execution.

This testbench does **not** need to test I2C protocol correctness — that is covered by `tb_i2c.vhd`. Here you verify:
- CPU boots and fetches instructions from `0x0000_xxxx`
- GPIO counter write reaches `0x2000_0000`
- After Day 5 integration: I2C register writes appear at `0x1000_0xxx`

---

## Entity Interface

```vhdl
entity tb_top_soc is
    -- Testbenches have no ports
end entity tb_top_soc;
```

---

## Architecture Overview

```vhdl
architecture sim of tb_top_soc is

    -- DUT signals
    signal clk_50mhz : std_logic := '0';
    signal reset_n   : std_logic := '0';
    signal i2c_scl   : std_logic;
    signal i2c_sda   : std_logic;
    signal gpio_out  : std_logic_vector(31 downto 0);

    -- Simulation control
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz
    constant RESET_HOLD : time := 200 ns; -- 10 clock cycles

begin
    -- Clock generator
    clk_50mhz <= not clk_50mhz after CLK_PERIOD / 2;

    -- Reset sequence
    process
    begin
        reset_n <= '0';
        wait for RESET_HOLD;
        reset_n <= '1';
        wait;
    end process;

    -- DUT instantiation
    u_dut : entity work.top_soc
        port map (
            clk_50mhz => clk_50mhz,
            reset_n   => reset_n,
            i2c_scl   => i2c_scl,
            i2c_sda   => i2c_sda,
            gpio_out  => gpio_out
        );

    -- I2C bus pull-ups (simulate 4.7 kΩ to VDD)
    i2c_scl <= 'H';  -- VHDL 'H' = weak '1' (pull-up)
    i2c_sda <= 'H';

    -- Simulation timeout and assertion checker
    process
    begin
        wait for 10_000 ns;  -- 10 µs = 500 cycles @ 50 MHz
        assert false report "Simulation complete (timeout)" severity note;
        wait;
    end process;

end architecture sim;
```

---

## What to Observe in Waveforms

Add these signals to the ModelSim wave window:

| Signal | Expected Behavior |
|--------|-------------------|
| `clk_50mhz` | 50 MHz clock |
| `reset_n` | Low for ~200 ns, then high |
| `u_dut/u_mem_bus/u_cpu/mem_valid` | Bursts of '1' during instruction fetches |
| `u_dut/u_mem_bus/u_cpu/mem_addr` | Starts at `0x00000000`, advances by 4 (or 2 for compressed) |
| `u_dut/u_mem_bus/u_cpu/mem_wstrb` | `0000` for fetches, `1111` for word writes |
| `u_dut/gpio_out` | Increments from 0 after CPU runs counter loop |
| `u_dut/i2c_scl` | Pulled high by 'H', then I2C clock after Day 5 |
| `u_dut/i2c_sda` | Pulled high by 'H', then address/data after Day 5 |

---

## Simulation Script for ModelSim

Create a `sim/run_tb_top_soc.tcl` script:

```tcl
# ModelSim simulation script for tb_top_soc
vlib work

# Compile VHDL sources (VHDL 2008)
vcom -2008 ../rtl/onchip_ram.vhd
vcom -2008 ../rtl/i2c_controller.vhd
vcom -2008 ../rtl/mem_bus.vhd
vcom -2008 ../rtl/top_soc.vhd
vcom -2008 ../tb/tb_top_soc.vhd

# Compile Verilog (PicoRV32)
vlog ../picorv32/picorv32.v

# Simulate
vsim work.tb_top_soc

# Add waveforms
add wave -divider "Clock & Reset"
add wave /tb_top_soc/clk_50mhz
add wave /tb_top_soc/reset_n

add wave -divider "CPU Bus"
add wave -hex /tb_top_soc/u_dut/mem_valid
add wave -hex /tb_top_soc/u_dut/mem_ready
add wave -hex /tb_top_soc/u_dut/mem_addr
add wave -hex /tb_top_soc/u_dut/mem_wdata
add wave -hex /tb_top_soc/u_dut/mem_wstrb
add wave -hex /tb_top_soc/u_dut/mem_rdata

add wave -divider "GPIO"
add wave -hex /tb_top_soc/gpio_out

add wave -divider "I2C"
add wave /tb_top_soc/i2c_scl
add wave /tb_top_soc/i2c_sda

# Run
run 10 us

# Save waveform
write format wave -window .wave wave_top_soc.do
```

---

## Verification Checklist

After running the simulation, verify each of these before moving on:

- [ ] `mem_addr` starts at `0x00000000` immediately after reset release
- [ ] `mem_valid` and `mem_ready` handshake correctly (ready follows valid by 0–1 cycles)
- [ ] `mem_addr` advances sequentially through the instruction memory (`0x00000000`, `0x00000004`, ...)
- [ ] CPU executes the loop in `main.c` and writes incrementing values to `mem_addr = 0x20000000`
- [ ] `gpio_out` changes over time (confirms CPU is running, not stuck)
- [ ] No `trap` signal assertion (trap indicates illegal instruction or bus fault)

---

## Common Simulation Problems

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `mem_addr` stuck at `0x00000000` | Reset not releasing, or `mem_ready` never high | Check `pll_locked` simulation behavior; tie `pll_locked = '1'` in sim |
| `gpio_out` never changes | Firmware not reaching GPIO write | Check `.mif` loaded correctly; add more sim time |
| `mem_rdata` always `0x00000000` | `.mif` file not found by ModelSim | Set ModelSim working directory to Quartus project folder |
| `trap` asserts | Illegal instruction or NACK fault | Verify firmware compiled with `-march=rv32imc` |
| Waveforms show `X` (unknown) | Reset not synchronized | Ensure reset is applied for at least 2 `clk_sys` cycles |
