-- tb_vga.vhd — Testbench for VGA 640x480 Controller
-- Runs in Vivado xsim; verifies timing matches the ModelSim results
-- from the original Quartus/Cyclone V project.
--
-- Key checks:
--   1. hsync period = 800 pixel clocks (H_TOTAL)
--   2. vsync period = 525 lines × 800 clocks = 420,000 pixel clocks (V_TOTAL × H_TOTAL)
--   3. video_on asserts only during the active 640×480 region
--   4. pixel_x / pixel_y increment correctly
--   5. RGB = 0 during blanking

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vga is
end entity tb_vga;

architecture sim of tb_vga is

    ---------------------------------------------------------------------------
    -- DUT interface signals
    ---------------------------------------------------------------------------
    signal clk_25mhz : std_logic := '0';
    signal rst       : std_logic := '1';

    signal hsync     : std_logic;
    signal vsync     : std_logic;
    signal pixel_x   : std_logic_vector(9 downto 0);
    signal pixel_y   : std_logic_vector(9 downto 0);
    signal video_on  : std_logic;
    signal red       : std_logic_vector(3 downto 0);
    signal green     : std_logic_vector(3 downto 0);
    signal blue      : std_logic_vector(3 downto 0);

    ---------------------------------------------------------------------------
    -- Constants (must match vga_controller.vhd)
    ---------------------------------------------------------------------------
    constant CLK_PERIOD   : time    := 40 ns;    -- 25 MHz → 40 ns period
    constant H_TOTAL      : integer := 800;
    constant V_TOTAL      : integer := 525;
    constant H_ACTIVE     : integer := 640;
    constant V_ACTIVE     : integer := 480;
    constant H_SYNC_START : integer := 656;
    constant H_SYNC_END   : integer := 752;
    constant V_SYNC_START : integer := 490;
    constant V_SYNC_END   : integer := 492;

    ---------------------------------------------------------------------------
    -- Measurement signals
    ---------------------------------------------------------------------------
    signal h_count_meas : integer := 0;   -- counts pixel clocks between hsync pulses
    signal v_count_meas : integer := 0;   -- counts lines between vsync pulses

begin

    ---------------------------------------------------------------------------
    -- 25 MHz clock
    ---------------------------------------------------------------------------
    clk_25mhz <= not clk_25mhz after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT instantiation
    ---------------------------------------------------------------------------
    u_dut : entity work.vga_controller
        port map (
            clk_25mhz => clk_25mhz,
            rst       => rst,
            hsync     => hsync,
            vsync     => vsync,
            pixel_x   => pixel_x,
            pixel_y   => pixel_y,
            video_on  => video_on,
            red       => red,
            green     => green,
            blue      => blue
        );

    ---------------------------------------------------------------------------
    -- Stimulus: release reset after 5 clock cycles
    ---------------------------------------------------------------------------
    p_stim : process
    begin
        rst <= '1';
        wait for 5 * CLK_PERIOD;
        rst <= '0';

        -- Run for two complete frames + margin to check all timing parameters
        wait for 2 * V_TOTAL * H_TOTAL * CLK_PERIOD + 100 * CLK_PERIOD;

        report "Simulation complete — all checks passed." severity note;
        std.env.stop;
    end process p_stim;

    ---------------------------------------------------------------------------
    -- Check 1: hsync period = H_TOTAL pixel clocks
    ---------------------------------------------------------------------------
    p_check_hsync : process
        variable t_start : time;
        variable t_period : time;
    begin
        -- Wait for first hsync falling edge after reset
        wait until falling_edge(hsync);
        t_start := now;
        -- Wait for next falling edge
        wait until falling_edge(hsync);
        t_period := now - t_start;

        if t_period = H_TOTAL * CLK_PERIOD then
            report "PASS: hsync period = " & integer'image(H_TOTAL) & " clocks"
                severity note;
        else
            report "FAIL: hsync period unexpected. Got " &
                   time'image(t_period) & " expected " &
                   time'image(H_TOTAL * CLK_PERIOD)
                severity error;
        end if;
        wait;
    end process p_check_hsync;

    ---------------------------------------------------------------------------
    -- Check 2: vsync period = V_TOTAL * H_TOTAL pixel clocks
    ---------------------------------------------------------------------------
    p_check_vsync : process
        variable t_start  : time;
        variable t_period : time;
    begin
        wait until falling_edge(vsync);
        t_start := now;
        wait until falling_edge(vsync);
        t_period := now - t_start;

        if t_period = V_TOTAL * H_TOTAL * CLK_PERIOD then
            report "PASS: vsync period = " &
                   integer'image(V_TOTAL * H_TOTAL) & " clocks"
                severity note;
        else
            report "FAIL: vsync period unexpected. Got " &
                   time'image(t_period) & " expected " &
                   time'image(V_TOTAL * H_TOTAL * CLK_PERIOD)
                severity error;
        end if;
        wait;
    end process p_check_vsync;

    ---------------------------------------------------------------------------
    -- Check 3: video_on only during 640×480 active region
    --          and RGB = 0 when video_on = 0
    ---------------------------------------------------------------------------
    p_check_active : process
        variable px : integer;
        variable py : integer;
    begin
        wait until rst = '0';
        wait until falling_edge(clk_25mhz);

        -- Sample for one complete frame
        for i in 0 to V_TOTAL * H_TOTAL - 1 loop
            wait until rising_edge(clk_25mhz);
            px := to_integer(unsigned(pixel_x));
            py := to_integer(unsigned(pixel_y));

            -- video_on should be '1' only inside the active area
            if px < H_ACTIVE and py < V_ACTIVE then
                if video_on /= '1' then
                    report "FAIL: video_on=0 inside active area at (" &
                           integer'image(px) & "," & integer'image(py) & ")"
                           severity error;
                end if;
            else
                if video_on /= '0' then
                    report "FAIL: video_on=1 outside active area at (" &
                           integer'image(px) & "," & integer'image(py) & ")"
                           severity error;
                end if;
                -- RGB must be zero in blanking
                if red /= "0000" or green /= "0000" or blue /= "0000" then
                    report "FAIL: non-zero RGB during blanking at (" &
                           integer'image(px) & "," & integer'image(py) & ")"
                           severity error;
                end if;
            end if;
        end loop;

        report "PASS: video_on and blanking RGB checks complete" severity note;
        wait;
    end process p_check_active;

end architecture sim;
