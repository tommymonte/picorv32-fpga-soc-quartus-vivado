-- tb_top_soc.vhd — Top-Level SoC Testbench
-- Drives clock and reset into top_soc, observes GPIO counter output.
-- Does NOT test I2C — that is covered by tb_i2c.vhd.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_top_soc is
    -- Testbenches have no ports
end entity tb_top_soc;

architecture sim of tb_top_soc is

    -- DUT signals
    signal clk_50mhz : std_logic := '0';
    signal reset_n   : std_logic := '0';
    signal i2c_scl   : std_logic;
    signal i2c_sda   : std_logic;
    signal gpio_out  : std_logic_vector(31 downto 0);

    -- Simulation control
    constant CLK_PERIOD : time := 20 ns;   -- 50 MHz
    constant RESET_HOLD : time := 200 ns;  -- 10 clock cycles

begin

    ---------------------------------------------------------------------------
    -- Clock generator (50 MHz)
    ---------------------------------------------------------------------------
    clk_50mhz <= not clk_50mhz after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- Reset sequence
    ---------------------------------------------------------------------------
    process
    begin
        reset_n <= '0';
        wait for RESET_HOLD;
        reset_n <= '1';
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- DUT instantiation
    ---------------------------------------------------------------------------
    u_dut : entity work.top_soc
        port map (
            clk_50mhz => clk_50mhz,
            reset_n   => reset_n,
            i2c_scl   => i2c_scl,
            i2c_sda   => i2c_sda,
            gpio_out  => gpio_out
        );

    ---------------------------------------------------------------------------
    -- I2C bus pull-ups (simulate weak pull-up resistors)
    ---------------------------------------------------------------------------
    i2c_scl <= 'H';
    i2c_sda <= 'H';

    ---------------------------------------------------------------------------
    -- Simulation monitor: report GPIO changes and timeout
    ---------------------------------------------------------------------------
    process
    begin
        wait for 10_000 ns;  -- 10 us = ~250 cycles @ 25 MHz system clock
        assert false report "Simulation complete (timeout)" severity note;
        wait;
    end process;

    -- Report when GPIO output first becomes non-zero (CPU is running)
    process
    begin
        wait until gpio_out /= x"00000000";
        assert false
            report "GPIO output detected: CPU is executing firmware"
            severity note;
        wait;
    end process;

end architecture sim;
