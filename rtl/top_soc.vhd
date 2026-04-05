-- top_soc.vhd — Top-Level SoC
-- Root of the design hierarchy. Instantiates PLL, PicoRV32 CPU, and mem_bus.
-- Quartus synthesis top-level entity. Testbench instantiates this directly.

library ieee;
use ieee.std_logic_1164.all;

entity top_soc is
    port (
        -- Board inputs
        clk_50mhz : in  std_logic;                    -- 50 MHz oscillator
        reset_n   : in  std_logic;                    -- Active-low reset

        -- I2C pins (open-drain, directly exposed)
        i2c_scl   : inout std_logic;
        i2c_sda   : inout std_logic;

        -- GPIO (simulation visibility of counter)
        gpio_out  : out std_logic_vector(31 downto 0)
    );
end entity top_soc;

architecture rtl of top_soc is

    ---------------------------------------------------------------------------
    -- Component declarations (external IP: PLL + PicoRV32 Verilog core)
    ---------------------------------------------------------------------------
    component pll_25mhz is
        port (
            inclk0 : in  std_logic;
            c0     : out std_logic;
            locked : out std_logic
        );
    end component pll_25mhz;

    component picorv32 is
        generic (
            COMPRESSED_ISA : integer := 0;
            ENABLE_MUL     : integer := 0;
            ENABLE_DIV     : integer := 0;
            BARREL_SHIFTER : integer := 0
        );
        port (
            clk       : in  std_logic;
            resetn    : in  std_logic;
            trap      : out std_logic;

            mem_valid  : out std_logic;
            mem_instr  : out std_logic;
            mem_ready  : in  std_logic;
            mem_addr   : out std_logic_vector(31 downto 0);
            mem_wdata  : out std_logic_vector(31 downto 0);
            mem_wstrb  : out std_logic_vector( 3 downto 0);
            mem_rdata  : in  std_logic_vector(31 downto 0);

            -- Unused look-ahead / IRQ / trace ports — directly tie off
            mem_la_read  : out std_logic;
            mem_la_write : out std_logic;
            mem_la_addr  : out std_logic_vector(31 downto 0);
            mem_la_wdata : out std_logic_vector(31 downto 0);
            mem_la_wstrb : out std_logic_vector( 3 downto 0);

            irq  : in  std_logic_vector(31 downto 0);
            eoi  : out std_logic_vector(31 downto 0);

            trace_valid : out std_logic;
            trace_data  : out std_logic_vector(35 downto 0)
        );
    end component picorv32;

    ---------------------------------------------------------------------------
    -- Internal signals
    ---------------------------------------------------------------------------

    -- Clock/reset
    signal clk_sys    : std_logic;
    signal pll_locked : std_logic;
    signal rst        : std_logic;
    signal cpu_resetn : std_logic;   -- M-03 fix: intermediate for port map

    -- PicoRV32 memory bus
    signal mem_valid  : std_logic;
    signal mem_ready  : std_logic;
    signal mem_addr   : std_logic_vector(31 downto 0);
    signal mem_wdata  : std_logic_vector(31 downto 0);
    signal mem_wstrb  : std_logic_vector( 3 downto 0);
    signal mem_rdata  : std_logic_vector(31 downto 0);

    -- Trap (useful for simulation debug)
    signal trap       : std_logic;

begin

    ---------------------------------------------------------------------------
    -- 1. PLL (50 MHz -> 25 MHz)  — Quartus ALTPLL megafunction
    ---------------------------------------------------------------------------
    u_pll : pll_25mhz
        port map (
            inclk0 => clk_50mhz,
            c0     => clk_sys,
            locked => pll_locked
        );

    ---------------------------------------------------------------------------
    -- 2. Reset synchronizer (combinatorial, sufficient for this project)
    --    Hold reset until PLL locked AND external reset released.
    ---------------------------------------------------------------------------
    rst        <= (not reset_n) or (not pll_locked);
    cpu_resetn <= not rst;   -- M-03 fix: drive signal, then map it

    ---------------------------------------------------------------------------
    -- 3. PicoRV32 CPU (Verilog — requires mixed-language in Quartus)
    ---------------------------------------------------------------------------
    u_cpu : picorv32
        generic map (
            COMPRESSED_ISA => 1,    -- RV32IMC: 'C' extension
            ENABLE_MUL     => 1,    -- 'M' extension: multiply
            ENABLE_DIV     => 1,    -- 'M' extension: divide
            BARREL_SHIFTER => 1     -- Fast shifts
        )
        port map (
            clk       => clk_sys,
            resetn    => cpu_resetn,
            trap      => trap,

            mem_valid  => mem_valid,
            mem_instr  => open,
            mem_ready  => mem_ready,
            mem_addr   => mem_addr,
            mem_wdata  => mem_wdata,
            mem_wstrb  => mem_wstrb,
            mem_rdata  => mem_rdata,

            mem_la_read  => open,
            mem_la_write => open,
            mem_la_addr  => open,
            mem_la_wdata => open,
            mem_la_wstrb => open,

            irq  => (others => '0'),
            eoi  => open,

            trace_valid => open,
            trace_data  => open
        );

    ---------------------------------------------------------------------------
    -- 4. Memory Bus (RAM + GPIO + I2C stub)
    ---------------------------------------------------------------------------
    u_mem_bus : entity work.mem_bus
        port map (
            clk       => clk_sys,
            rst       => rst,

            mem_valid  => mem_valid,
            mem_ready  => mem_ready,
            mem_addr   => mem_addr,
            mem_wdata  => mem_wdata,
            mem_wstrb  => mem_wstrb,
            mem_rdata  => mem_rdata,

            gpio_out   => gpio_out,

            i2c_scl    => i2c_scl,
            i2c_sda    => i2c_sda
        );

end architecture rtl;
