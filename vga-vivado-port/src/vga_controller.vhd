-- vga_controller.vhd — VGA 640x480 @ 60 Hz Timing Generator
-- Ported unchanged from Quartus/Cyclone V to Vivado/Artix-7.
-- Only the vendor IP wrapper (PLL, ROM) changes; this file stays identical.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_controller is
    port (
        clk_25mhz  : in  std_logic;         -- Pixel clock input (25 MHz)
        rst        : in  std_logic;          -- Synchronous reset, active-high

        -- VGA sync outputs
        hsync      : out std_logic;          -- Horizontal sync (active low)
        vsync      : out std_logic;          -- Vertical sync (active low)

        -- Current pixel coordinates
        pixel_x    : out std_logic_vector(9 downto 0);  -- 0..639
        pixel_y    : out std_logic_vector(9 downto 0);  -- 0..479
        video_on   : out std_logic;          -- '1' during active display area

        -- RGB output (to VGA DAC or direct I/O pins)
        red        : out std_logic_vector(3 downto 0);
        green      : out std_logic_vector(3 downto 0);
        blue       : out std_logic_vector(3 downto 0)
    );
end entity vga_controller;

architecture rtl of vga_controller is

    ---------------------------------------------------------------------------
    -- VGA 640×480 @ 60 Hz timing constants
    --
    -- Horizontal (pixels):
    --   Active     640   Front porch  16   Sync  96  Back porch  48  Total 800
    -- Vertical (lines):
    --   Active     480   Front porch  10   Sync   2  Back porch  33  Total 525
    ---------------------------------------------------------------------------
    constant H_ACTIVE  : integer := 640;
    constant H_FP      : integer := 16;
    constant H_SYNC    : integer := 96;
    constant H_BP      : integer := 48;
    constant H_TOTAL   : integer := 800;   -- H_ACTIVE + H_FP + H_SYNC + H_BP

    constant H_SYNC_START : integer := H_ACTIVE + H_FP;          -- 656
    constant H_SYNC_END   : integer := H_ACTIVE + H_FP + H_SYNC; -- 752

    constant V_ACTIVE  : integer := 480;
    constant V_FP      : integer := 10;
    constant V_SYNC    : integer := 2;
    constant V_BP      : integer := 33;
    constant V_TOTAL   : integer := 525;

    constant V_SYNC_START : integer := V_ACTIVE + V_FP;          -- 490
    constant V_SYNC_END   : integer := V_ACTIVE + V_FP + V_SYNC; -- 492

    ---------------------------------------------------------------------------
    -- Counters
    ---------------------------------------------------------------------------
    signal h_cnt : unsigned(9 downto 0);   -- 0..799
    signal v_cnt : unsigned(9 downto 0);   -- 0..524

    signal video_active : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Horizontal counter
    ---------------------------------------------------------------------------
    p_hcnt : process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if rst = '1' or h_cnt = H_TOTAL - 1 then
                h_cnt <= (others => '0');
            else
                h_cnt <= h_cnt + 1;
            end if;
        end if;
    end process p_hcnt;

    ---------------------------------------------------------------------------
    -- Vertical counter — increments once per complete scan line
    ---------------------------------------------------------------------------
    p_vcnt : process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if rst = '1' then
                v_cnt <= (others => '0');
            elsif h_cnt = H_TOTAL - 1 then
                if v_cnt = V_TOTAL - 1 then
                    v_cnt <= (others => '0');
                else
                    v_cnt <= v_cnt + 1;
                end if;
            end if;
        end if;
    end process p_vcnt;

    ---------------------------------------------------------------------------
    -- Sync pulses (active low)
    ---------------------------------------------------------------------------
    hsync <= '0' when (h_cnt >= H_SYNC_START and h_cnt < H_SYNC_END) else '1';
    vsync <= '0' when (v_cnt >= V_SYNC_START and v_cnt < V_SYNC_END) else '1';

    ---------------------------------------------------------------------------
    -- Active display area and pixel coordinates
    ---------------------------------------------------------------------------
    video_active <= '1' when (h_cnt < H_ACTIVE and v_cnt < V_ACTIVE) else '0';

    video_on <= video_active;
    pixel_x  <= std_logic_vector(h_cnt);
    pixel_y  <= std_logic_vector(v_cnt);

    ---------------------------------------------------------------------------
    -- RGB output: generate a simple colour-bar test pattern when video is on.
    -- The pattern divides the horizontal active area into 8 equal bars.
    -- During blanking, RGB must be driven to 0 (VGA spec requirement).
    ---------------------------------------------------------------------------
    p_rgb : process(video_active, h_cnt)
        variable bar : unsigned(2 downto 0);
    begin
        if video_active = '0' then
            red   <= (others => '0');
            green <= (others => '0');
            blue  <= (others => '0');
        else
            -- Each bar is 640/8 = 80 pixels wide
            bar := h_cnt(9 downto 7);  -- bits [9:7] give 0..7 across 640 px
            red   <= (others => bar(2));
            green <= (others => bar(1));
            blue  <= (others => bar(0));
        end if;
    end process p_rgb;

end architecture rtl;
