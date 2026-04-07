-- tb_i2c.vhd — I2C Controller Standalone Testbench
-- Verifies i2c_controller.vhd in isolation before SoC integration.
-- Tests i2c_write_byte(slave_addr=0x50, data=0xAB) with a minimal
-- slave model that ACKs every byte.

library ieee;
use ieee.std_logic_1164.all;

entity tb_i2c is
end entity tb_i2c;

architecture sim of tb_i2c is

    constant CLK_PERIOD : time := 40 ns;  -- 25 MHz

    -- DUT signals
    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal addr  : std_logic_vector(1 downto 0) := "00";
    signal wdata : std_logic_vector(7 downto 0) := (others => '0');
    signal rdata : std_logic_vector(31 downto 0);
    signal wen   : std_logic := '0';
    signal ren   : std_logic := '0';
    signal ready : std_logic;

    -- I2C bus
    signal scl : std_logic;
    signal sda : std_logic;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- I2C pull-ups (weak high)
    scl <= 'H';
    sda <= 'H';

    -- DUT
    u_dut : entity work.i2c_controller
        generic map (
            SYS_CLK_HZ => 25_000_000,
            I2C_CLK_HZ => 100_000
        )
        port map (
            clk   => clk,
            rst   => rst,
            addr  => addr,
            wdata => wdata,
            rdata => rdata,
            wen   => wen,
            ren   => ren,
            ready => ready,
            scl   => scl,
            sda   => sda
        );

    ---------------------------------------------------------------------------
    -- Stimulus: simulates i2c_write_byte(0x50, 0xAB)
    ---------------------------------------------------------------------------
    stimulus : process

        -- Write one register (asserts wen for one clock cycle)
        procedure reg_write (
            reg  : in std_logic_vector(1 downto 0);
            data : in std_logic_vector(7 downto 0)
        ) is
        begin
            addr  <= reg;
            wdata <= data;
            wen   <= '1';
            wait until rising_edge(clk);
            wen   <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- Poll STATUS.BUSY until clear (with timeout)
        procedure wait_busy is
            variable timeout : integer := 0;
        begin
            addr <= "01";
            ren  <= '1';
            poll : loop
                wait until rising_edge(clk);
                exit poll when rdata(0) = '0';
                timeout := timeout + 1;
                assert timeout < 100000
                    report "BUSY timeout — FSM stuck" severity failure;
            end loop;
            ren <= '0';
            wait until rising_edge(clk);
        end procedure;

    begin
        -- Hold reset
        rst <= '1';
        wait for 200 ns;
        rst <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- Phase 1: Address byte (0x50 << 1 | W=0 = 0xA0)
        -----------------------------------------------------------------
        reg_write("10", x"A0");       -- TX_DATA = 0xA0
        reg_write("00", x"03");       -- CTRL = EN | START
        wait_busy;

        -- Check STATUS: ACK received, no error
        addr <= "01";
        ren  <= '1';
        wait until rising_edge(clk);
        ren  <= '0';
        assert rdata(1) = '1'
            report "Phase 1: ACK not received after address byte"
            severity error;
        assert rdata(2) = '0'
            report "Phase 1: ERROR flag set unexpectedly"
            severity error;
        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- Phase 2: Data byte (0xAB) with STOP
        -----------------------------------------------------------------
        reg_write("10", x"AB");       -- TX_DATA = 0xAB
        reg_write("00", x"05");       -- CTRL = EN | STOP
        wait_busy;

        -- Check STATUS: ACK received, no error
        addr <= "01";
        ren  <= '1';
        wait until rising_edge(clk);
        ren  <= '0';
        assert rdata(1) = '1'
            report "Phase 2: ACK not received after data byte"
            severity error;
        assert rdata(2) = '0'
            report "Phase 2: ERROR flag set unexpectedly"
            severity error;

        -- Clear CTRL
        reg_write("00", x"00");

        report "=== TEST PASSED: i2c_write_byte(0x50, 0xAB) ===" severity note;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Minimal I2C slave: ACKs every byte, verifies received data
    ---------------------------------------------------------------------------
    i2c_slave : process
        variable rx_byte : std_logic_vector(7 downto 0);
    begin
        sda <= 'Z';  -- Initialize driver to high-impedance

        -- Wait for START: SDA falls while SCL is high
        wait until falling_edge(sda) and to_x01(scl) = '1';

        ---------------------------------------------------------------
        -- Byte 1: address byte (expect 0xA0)
        ---------------------------------------------------------------
        for i in 7 downto 0 loop
            wait until rising_edge(scl);
            rx_byte(i) := to_x01(sda);
        end loop;
        assert rx_byte = x"A0"
            report "Slave: expected address byte 0xA0" severity error;

        -- ACK: pull SDA low during 9th clock
        wait until falling_edge(scl);
        sda <= '0';
        wait until rising_edge(scl);
        wait until falling_edge(scl);
        sda <= 'Z';

        ---------------------------------------------------------------
        -- Byte 2: data byte (expect 0xAB)
        ---------------------------------------------------------------
        for i in 7 downto 0 loop
            wait until rising_edge(scl);
            rx_byte(i) := to_x01(sda);
        end loop;
        assert rx_byte = x"AB"
            report "Slave: expected data byte 0xAB" severity error;

        -- ACK byte 2
        wait until falling_edge(scl);
        sda <= '0';
        wait until rising_edge(scl);
        wait until falling_edge(scl);
        sda <= 'Z';

        ---------------------------------------------------------------
        -- Wait for STOP: SDA rises while SCL is high
        ---------------------------------------------------------------
        wait until rising_edge(sda) and to_x01(scl) = '1';

        report "=== I2C slave: STOP detected, transaction complete ===" severity note;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Safety timeout
    ---------------------------------------------------------------------------
    timeout : process
    begin
        wait for 1 ms;
        assert false report "Simulation timeout (1 ms)" severity failure;
        wait;
    end process;

end architecture sim;
