-- mem_bus.vhd — Memory Bus / Address Decoder
-- Sits between PicoRV32 CPU and all memory-mapped slaves.
-- Combinatorial address decoder + mem_ready multiplexer.
-- I2C controller instantiation deferred to step 13.

library ieee;
use ieee.std_logic_1164.all;

entity mem_bus is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- PicoRV32 master port
        mem_valid : in  std_logic;
        mem_ready : out std_logic;
        mem_addr  : in  std_logic_vector(31 downto 0);
        mem_wdata : in  std_logic_vector(31 downto 0);
        mem_wstrb : in  std_logic_vector( 3 downto 0);
        mem_rdata : out std_logic_vector(31 downto 0);

        -- Slave: GPIO (internal register)
        gpio_out  : out std_logic_vector(31 downto 0);

        -- Slave: I2C controller (directly exposed for top-level connection)
        i2c_scl   : inout std_logic;
        i2c_sda   : inout std_logic
    );
end entity mem_bus;

architecture rtl of mem_bus is

    -- Address decode chip-selects
    signal sel_ram  : std_logic;
    signal sel_i2c  : std_logic;
    signal sel_gpio : std_logic;

    -- RAM interface signals
    signal ram_addr  : std_logic_vector(11 downto 0);  -- 12-bit word address (N-04 fix)
    signal ram_rdata : std_logic_vector(31 downto 0);
    signal ram_ready : std_logic;

    -- I2C stub signals (will be driven by i2c_controller in step 13)
    signal i2c_rdata : std_logic_vector(31 downto 0);
    signal i2c_ready : std_logic;

    -- GPIO register
    signal gpio_reg  : std_logic_vector(31 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Address decode (combinatorial) — uses mem_addr[31:28]
    ---------------------------------------------------------------------------
    sel_ram  <= '1' when mem_addr(31 downto 28) = x"0" else '0';
    sel_i2c  <= '1' when mem_addr(31 downto 28) = x"1" else '0';
    sel_gpio <= '1' when mem_addr(31 downto 28) = x"2" else '0';

    ---------------------------------------------------------------------------
    -- RAM word address — strip byte bits [1:0] and upper bits [31:14]
    -- 12-bit word address -> 4K words (16 KB)  (N-01 fix)
    ---------------------------------------------------------------------------
    ram_addr <= mem_addr(13 downto 2);

    ---------------------------------------------------------------------------
    -- On-chip RAM instantiation
    ---------------------------------------------------------------------------
    u_ram : entity work.onchip_ram
        port map (
            clk   => clk,
            en    => sel_ram and mem_valid,
            addr  => ram_addr,
            wdata => mem_wdata,
            wstrb => mem_wstrb,
            rdata => ram_rdata,
            ready => ram_ready
        );

    ---------------------------------------------------------------------------
    -- I2C controller — stub until step 13
    -- Selecting the I2C range will not assert ready (CPU stalls),
    -- which is safe because firmware does not access I2C yet.
    ---------------------------------------------------------------------------
    i2c_rdata <= (others => '0');
    i2c_ready <= '0';
    i2c_scl   <= 'Z';
    i2c_sda   <= 'Z';

    ---------------------------------------------------------------------------
    -- GPIO output register
    ---------------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                gpio_reg <= (others => '0');
            elsif sel_gpio = '1' and mem_valid = '1'
                  and (mem_wstrb(3) or mem_wstrb(2)       -- M-01 fix:
                       or mem_wstrb(1) or mem_wstrb(0)) = '1' then  -- explicit OR
                gpio_reg <= mem_wdata;
            end if;
        end if;
    end process;

    gpio_out <= gpio_reg;

    ---------------------------------------------------------------------------
    -- mem_ready mux — only one slave can be selected at a time
    ---------------------------------------------------------------------------
    mem_ready <= (sel_ram  and ram_ready)
              or (sel_i2c  and i2c_ready)
              or (sel_gpio and mem_valid);   -- GPIO: combinatorial single-cycle

    ---------------------------------------------------------------------------
    -- mem_rdata mux
    ---------------------------------------------------------------------------
    mem_rdata <= ram_rdata  when sel_ram  = '1' else
                 i2c_rdata  when sel_i2c  = '1' else
                 gpio_reg   when sel_gpio = '1' else
                 (others => '0');

end architecture rtl;
