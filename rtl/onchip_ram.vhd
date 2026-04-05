-- onchip_ram.vhd — 16 KB on-chip RAM using Intel altsyncram
-- Initialized from .mif file at synthesis time.
-- Single-port, byte-enable writes, unregistered read output.

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity onchip_ram is
    generic (
        ADDR_WIDTH : integer := 12;       -- 2^12 = 4096 words = 16 KB
        MIF_FILE   : string  := "fw.mif"
    );
    port (
        clk   : in  std_logic;
        en    : in  std_logic;                        -- Enable (sel_ram AND mem_valid)
        addr  : in  std_logic_vector(11 downto 0);   -- Word address [13:2]
        wdata : in  std_logic_vector(31 downto 0);   -- Write data
        wstrb : in  std_logic_vector( 3 downto 0);   -- Byte enables
        rdata : out std_logic_vector(31 downto 0);   -- Read data (combinatorial)
        ready : out std_logic                         -- Transaction complete
    );
end entity onchip_ram;

architecture rtl of onchip_ram is

    signal wren : std_logic;

begin

    -- Write enable: active when enabled and any byte lane is written
    wren <= en and (wstrb(3) or wstrb(2) or wstrb(1) or wstrb(0));

    -- Unregistered output: ready in same cycle as enable
    ready <= en;

    u_altsyncram : altsyncram
        generic map (
            operation_mode         => "SINGLE_PORT",
            width_a                => 32,
            widthad_a              => ADDR_WIDTH,
            numwords_a             => 2**ADDR_WIDTH,
            init_file              => MIF_FILE,
            init_file_layout       => "PORT_A",
            outdata_reg_a          => "UNREGISTERED",
            byte_size              => 8,
            width_byteena_a        => 4
        )
        port map (
            clock0    => clk,
            address_a => addr,
            data_a    => wdata,
            wren_a    => wren,
            byteena_a => wstrb,
            q_a       => rdata
        );

end architecture rtl;
