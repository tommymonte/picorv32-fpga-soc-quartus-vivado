# `rtl/top_soc.vhd` — Top-Level SoC

## Role in the System

This is the **root of the design hierarchy**. It does no logic itself — it only instantiates and wires together every sub-module. Quartus uses this file as the synthesis top-level entity. ModelSim's testbench (`tb_top_soc.vhd`) instantiates this entity directly.

---

## Entity Interface

```vhdl
entity top_soc is
    port (
        -- Board inputs
        clk_50mhz : in  std_logic;                    -- 50 MHz oscillator from Cyclone V board
        reset_n   : in  std_logic;                    -- Active-low reset (push button or SW)

        -- I2C pins (routed to external header / simulation probes)
        i2c_scl   : inout std_logic;                  -- Open-drain clock
        i2c_sda   : inout std_logic;                  -- Open-drain data

        -- Optional GPIO (for simulation visibility of counter)
        gpio_out  : out std_logic_vector(31 downto 0)
    );
end entity top_soc;
```

> `inout` ports on SCL/SDA are needed for synthesis (open-drain requires a tristate buffer). In simulation you can simplify to `out` if your testbench does not drive them back.

---

## Internal Signals

```vhdl
architecture rtl of top_soc is

    -- Clock after PLL
    signal clk_sys      : std_logic;
    signal pll_locked   : std_logic;

    -- Synchronous reset (active-high, derived from reset_n AND pll_locked)
    signal rst          : std_logic;

    -- PicoRV32 memory bus
    signal mem_valid    : std_logic;
    signal mem_ready    : std_logic;
    signal mem_addr     : std_logic_vector(31 downto 0);
    signal mem_wdata    : std_logic_vector(31 downto 0);
    signal mem_wstrb    : std_logic_vector( 3 downto 0);
    signal mem_rdata    : std_logic_vector(31 downto 0);

    -- Trap signal (optional — useful for simulation)
    signal trap         : std_logic;

begin
```

---

## Sub-Module Instantiations

### 1. PLL (50 MHz → 25 MHz)

Use the **ALTPLL** megafunction IP from Quartus. Generate it via the IP Catalog, then instantiate:

```vhdl
u_pll : entity work.pll_25mhz           -- generated Quartus megafunction
    port map (
        inclk0 => clk_50mhz,
        c0     => clk_sys,
        locked => pll_locked
    );
```

> In simulation, you can skip the PLL and drive `clk_sys` directly at 25 MHz from the testbench. Make `pll_locked` a tied constant `'1'`.

### 2. Reset Synchronizer

```vhdl
-- Hold reset until PLL is locked AND external reset is released
rst <= not reset_n or not pll_locked;
```

A proper design adds 2–3 flip-flop synchronizer stages, but for this project the combinatorial version is sufficient for simulation.

### 3. PicoRV32 CPU

PicoRV32 is a **Verilog** module. Quartus supports mixed-language (Verilog + VHDL) in the same project — just add `picorv32.v` to the project files alongside the VHDL files.

```vhdl
u_cpu : entity work.picorv32
    generic map (
        COMPRESSED_ISA => 1,    -- Enable 'C' extension (RV32IMC)
        ENABLE_MUL     => 1,    -- Enable 'M' extension (multiply)
        ENABLE_DIV     => 1,    -- Enable divide
        BARREL_SHIFTER => 1     -- Fast shifts (uses more LUTs)
    )
    port map (
        clk        => clk_sys,
        resetn     => not rst,  -- PicoRV32 uses active-low reset
        trap       => trap,

        mem_valid  => mem_valid,
        mem_ready  => mem_ready,
        mem_addr   => mem_addr,
        mem_wdata  => mem_wdata,
        mem_wstrb  => mem_wstrb,
        mem_rdata  => mem_rdata
    );
```

> Check the exact port names in `picorv32.v` — the interface has remained stable but confirm `mem_instr` if needed (instruction vs data fetch indicator, optional).

### 4. Memory Bus

```vhdl
u_mem_bus : entity work.mem_bus
    port map (
        clk        => clk_sys,
        rst        => rst,

        -- From CPU
        mem_valid  => mem_valid,
        mem_ready  => mem_ready,
        mem_addr   => mem_addr,
        mem_wdata  => mem_wdata,
        mem_wstrb  => mem_wstrb,
        mem_rdata  => mem_rdata,

        -- GPIO output (wired to top-level port)
        gpio_out   => gpio_out,

        -- I2C
        i2c_scl    => i2c_scl,
        i2c_sda    => i2c_sda
    );
```

---

## Reset Strategy

```
reset_n (async, active-low)   pll_locked
        │                          │
        └──────── OR gate ─────────┘
                       │
                      rst  (active-high, synchronous hold)
                       │
                  → PicoRV32 (resetn = NOT rst)
                  → mem_bus
                  → i2c_controller
```

Keep the CPU in reset until the PLL is stable. This prevents spurious instruction fetches during clock stabilization.

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Forgetting `COMPRESSED_ISA => 1` | CPU won't decode 16-bit instructions | Always match generic to `-march=rv32imc` |
| Driving `resetn` with async `reset_n` before PLL locked | CPU starts fetching before clock is stable | Gate reset on `pll_locked` |
| `inout` SCL/SDA without tristate buffer | DRC/synthesis error | Use `'Z'` when not driving |
| Mixed-language not enabled in Quartus | `picorv32.v` won't compile | Project → Settings → Files → enable Verilog |

---

## Simulation Notes

When simulating via `tb_top_soc.vhd`:
- Drive `clk_50mhz` at 20 ns period (50 MHz).
- Assert `reset_n = '0'` for at least 10 cycles, then release.
- The testbench does **not** need to model I2C slaves unless testing Day 5 integration.
- Watch `mem_addr` to confirm instruction fetches from `0x0000_xxxx` and GPIO writes to `0x2000_0000`.
