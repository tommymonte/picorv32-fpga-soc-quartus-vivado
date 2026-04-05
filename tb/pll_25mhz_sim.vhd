-- pll_25mhz_sim.vhd — Behavioral simulation model for ALTPLL
-- Divides 50 MHz input by 2 to produce 25 MHz output.
-- Asserts 'locked' after a short startup delay.
-- Compile into 'work' library so top_soc's component instantiation binds here.

library ieee;
use ieee.std_logic_1164.all;

entity pll_25mhz is
    port (
        inclk0 : in  std_logic;
        c0     : out std_logic;
        locked : out std_logic
    );
end entity pll_25mhz;

architecture sim of pll_25mhz is
    signal div2 : std_logic := '0';
begin

    -- Divide-by-2: 50 MHz -> 25 MHz
    process (inclk0)
    begin
        if rising_edge(inclk0) then
            div2 <= not div2;
        end if;
    end process;

    c0 <= div2;

    -- Assert locked after 5 input clock cycles (100 ns @ 50 MHz)
    process
    begin
        locked <= '0';
        for i in 0 to 4 loop
            wait until rising_edge(inclk0);
        end loop;
        locked <= '1';
        wait;
    end process;

end architecture sim;
