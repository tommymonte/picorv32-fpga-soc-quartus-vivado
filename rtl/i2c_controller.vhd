-- i2c_controller.vhd — I2C Master Controller
-- Memory-mapped I2C master with multi-phase FSM (C-01 Option A).
-- The FSM returns to IDLE after each byte ACK, allowing firmware to
-- control each phase independently via CTRL register writes.
--
-- Register map (addr[1:0]):
--   "00" CTRL    (W): [0]=EN, [1]=START, [2]=STOP, [3]=RW
--   "01" STATUS  (R): [0]=BUSY, [1]=ACK_RECV, [2]=ERROR
--   "10" TX_DATA (W): byte to transmit
--   "11" RX_DATA (R): last byte received
--
-- Repeated START is not supported; START must only be issued
-- when the bus is free (after reset or after STOP).

library ieee;
use ieee.std_logic_1164.all;

entity i2c_controller is
    generic (
        SYS_CLK_HZ : integer := 25_000_000;
        I2C_CLK_HZ : integer := 100_000
    );
    port (
        clk   : in    std_logic;
        rst   : in    std_logic;

        -- Register bus interface (from mem_bus)
        addr  : in    std_logic_vector(1 downto 0);
        wdata : in    std_logic_vector(7 downto 0);
        rdata : out   std_logic_vector(31 downto 0);
        wen   : in    std_logic;
        ren   : in    std_logic;
        ready : out   std_logic;

        -- I2C bus (open-drain)
        scl   : inout std_logic;
        sda   : inout std_logic
    );
end entity i2c_controller;

architecture rtl of i2c_controller is

    ---------------------------------------------------------------------------
    -- SCL clock divider: 25 MHz / (2 x 100 kHz) = 125 cycles per half-period
    ---------------------------------------------------------------------------
    constant SCL_HALF : integer := SYS_CLK_HZ / (2 * I2C_CLK_HZ);

    signal clk_cnt  : integer range 0 to SCL_HALF - 1;
    signal scl_tick : std_logic;

    ---------------------------------------------------------------------------
    -- FSM states — each state represents a unique SCL/SDA bus condition.
    -- Multi-phase per C-01: FSM parks in IDLE between byte phases.
    ---------------------------------------------------------------------------
    type i2c_state_t is (
        ST_IDLE,        -- Bus free or parked (SCL held low if bus_claimed)
        ST_START,       -- START hold: SDA low, SCL high
        ST_BIT_LOW,     -- Data bit: SCL low, SDA driven/released
        ST_BIT_HIGH,    -- Data bit: SCL high, sample window
        ST_ACK_LOW,     -- ACK setup: SCL low
        ST_ACK_HIGH,    -- ACK sample: SCL high
        ST_STOP_LOW,    -- STOP setup: SCL low, SDA low
        ST_STOP_HIGH    -- STOP hold: SCL high, then SDA rises
    );
    signal state : i2c_state_t;

    ---------------------------------------------------------------------------
    -- Registers
    ---------------------------------------------------------------------------
    signal tx_data_reg  : std_logic_vector(7 downto 0);
    signal rx_data_reg  : std_logic_vector(7 downto 0);

    -- CTRL fields (latched on write to addr "00")
    signal ctrl_en      : std_logic;
    signal ctrl_start   : std_logic;
    signal ctrl_stop    : std_logic;
    signal ctrl_rw      : std_logic;
    signal ctrl_written : std_logic;  -- single-cycle pulse

    ---------------------------------------------------------------------------
    -- Shift registers and bit counter
    ---------------------------------------------------------------------------
    signal tx_shift : std_logic_vector(7 downto 0);
    signal rx_shift : std_logic_vector(7 downto 0);
    signal bit_cnt  : integer range 0 to 7;

    ---------------------------------------------------------------------------
    -- Status
    ---------------------------------------------------------------------------
    signal ack_recv   : std_logic;
    signal error_flag : std_logic;
    signal busy       : std_logic;
    signal status_reg : std_logic_vector(7 downto 0);

    ---------------------------------------------------------------------------
    -- I2C line control
    ---------------------------------------------------------------------------
    signal scl_drive : std_logic;  -- '0' = pull low, '1' = release (high-Z)
    signal sda_drive : std_logic;
    signal sda_in    : std_logic;

    ---------------------------------------------------------------------------
    -- Transaction control
    ---------------------------------------------------------------------------
    signal stop_after  : std_logic;  -- latched CTRL.STOP for current phase
    signal is_read     : std_logic;  -- '1' = receive mode (master reads)
    signal bus_claimed : std_logic;  -- '1' = SCL held low between phases

begin

    ---------------------------------------------------------------------------
    -- Open-drain drivers
    ---------------------------------------------------------------------------
    scl <= '0' when scl_drive = '0' else 'Z';
    sda <= '0' when sda_drive = '0' else 'Z';

    -- Resolve 'Z'/'H' as '1' for input sampling (bus pulled up externally)
    sda_in <= '0' when sda = '0' else '1';

    ---------------------------------------------------------------------------
    -- Status register
    ---------------------------------------------------------------------------
    busy       <= '0' when state = ST_IDLE else '1';
    status_reg <= "00000" & error_flag & ack_recv & busy;

    ---------------------------------------------------------------------------
    -- Register read (combinatorial — single-cycle response)
    ---------------------------------------------------------------------------
    rdata <= x"000000" & status_reg  when addr = "01" else
             x"000000" & rx_data_reg when addr = "11" else
             (others => '0');

    ready <= wen or ren;

    ---------------------------------------------------------------------------
    -- Register write
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            ctrl_written <= '0';
            if rst = '1' then
                ctrl_en     <= '0';
                ctrl_start  <= '0';
                ctrl_stop   <= '0';
                ctrl_rw     <= '0';
                tx_data_reg <= (others => '0');
            elsif wen = '1' then
                case addr is
                    when "00" =>
                        ctrl_en      <= wdata(0);
                        ctrl_start   <= wdata(1);
                        ctrl_stop    <= wdata(2);
                        ctrl_rw      <= wdata(3);
                        ctrl_written <= '1';
                    when "10" =>
                        tx_data_reg  <= wdata;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- SCL clock divider — counter runs when FSM is active, resets in IDLE
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or state = ST_IDLE then
                clk_cnt  <= 0;
                scl_tick <= '0';
            elsif clk_cnt = SCL_HALF - 1 then
                clk_cnt  <= 0;
                scl_tick <= '1';
            else
                clk_cnt  <= clk_cnt + 1;
                scl_tick <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Main FSM
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state       <= ST_IDLE;
                scl_drive   <= '1';
                sda_drive   <= '1';
                bit_cnt     <= 0;
                tx_shift    <= (others => '0');
                rx_shift    <= (others => '0');
                rx_data_reg <= (others => '0');
                ack_recv    <= '0';
                error_flag  <= '0';
                stop_after  <= '0';
                is_read     <= '0';
                bus_claimed <= '0';
            else
                case state is

                    -------------------------------------------------------
                    -- IDLE: drive bus lines based on bus_claimed,
                    -- wait for CTRL write with EN=1
                    -------------------------------------------------------
                    when ST_IDLE =>
                        if bus_claimed = '0' then
                            scl_drive <= '1';  -- Released (high)
                            sda_drive <= '1';
                        else
                            scl_drive <= '0';  -- Held low between phases
                            sda_drive <= '1';
                        end if;

                        if ctrl_written = '1' and ctrl_en = '1' then
                            ack_recv   <= '0';
                            error_flag <= '0';
                            stop_after <= ctrl_stop;
                            tx_shift   <= tx_data_reg;
                            bit_cnt    <= 7;

                            if ctrl_start = '1' then
                                -- START: pull SDA low while SCL high
                                sda_drive   <= '0';
                                scl_drive   <= '1';
                                bus_claimed <= '1';
                                is_read     <= '0';  -- Address byte: always TX
                                state       <= ST_START;
                            else
                                -- Continue: SCL already low (bus_claimed)
                                is_read <= ctrl_rw;
                                if ctrl_rw = '1' then
                                    sda_drive <= '1';            -- Read: release SDA
                                else
                                    sda_drive <= tx_data_reg(7); -- Write: drive MSB
                                end if;
                                state <= ST_BIT_LOW;
                            end if;
                        end if;

                    -------------------------------------------------------
                    -- START: SDA low, SCL high — hold for one half-period.
                    -- Then pull SCL low and set up first data bit.
                    -------------------------------------------------------
                    when ST_START =>
                        if scl_tick = '1' then
                            scl_drive <= '0';          -- SCL falls
                            sda_drive <= tx_shift(7);  -- Set up MSB
                            state     <= ST_BIT_LOW;
                        end if;

                    -------------------------------------------------------
                    -- BIT_LOW: SCL low, SDA holds current bit value.
                    -- On tick: release SCL (rising edge).
                    -------------------------------------------------------
                    when ST_BIT_LOW =>
                        if scl_tick = '1' then
                            scl_drive <= '1';  -- SCL rises
                            state     <= ST_BIT_HIGH;
                        end if;

                    -------------------------------------------------------
                    -- BIT_HIGH: SCL high — sample window.
                    -- On tick: pull SCL low, advance to next bit or ACK.
                    -------------------------------------------------------
                    when ST_BIT_HIGH =>
                        if scl_tick = '1' then
                            rx_shift  <= rx_shift(6 downto 0) & sda_in;
                            scl_drive <= '0';  -- SCL falls

                            if bit_cnt > 0 then
                                bit_cnt <= bit_cnt - 1;
                                if is_read = '1' then
                                    sda_drive <= '1';          -- Read: SDA released
                                else
                                    tx_shift  <= tx_shift(6 downto 0) & '0';
                                    sda_drive <= tx_shift(6);  -- Write: next bit
                                end if;
                                state <= ST_BIT_LOW;
                            else
                                -- All 8 bits shifted — set up ACK
                                if is_read = '1' then
                                    -- Master ACK/NACK: NACK on last byte (STOP set)
                                    if stop_after = '1' then
                                        sda_drive <= '1';  -- NACK
                                    else
                                        sda_drive <= '0';  -- ACK
                                    end if;
                                else
                                    -- Write: release SDA for slave ACK
                                    sda_drive <= '1';
                                end if;
                                state <= ST_ACK_LOW;
                            end if;
                        end if;

                    -------------------------------------------------------
                    -- ACK_LOW: SCL low, ACK/NACK set up on SDA.
                    -- On tick: release SCL (rising edge).
                    -------------------------------------------------------
                    when ST_ACK_LOW =>
                        if scl_tick = '1' then
                            scl_drive <= '1';  -- SCL rises
                            state     <= ST_ACK_HIGH;
                        end if;

                    -------------------------------------------------------
                    -- ACK_HIGH: SCL high — sample slave ACK (write mode)
                    -- or hold master ACK (read mode).
                    -- On tick: pull SCL low, decide STOP or return to IDLE.
                    -------------------------------------------------------
                    when ST_ACK_HIGH =>
                        if scl_tick = '1' then
                            scl_drive <= '0';  -- SCL falls

                            if is_read = '0' then
                                -- Write mode: check slave's ACK
                                if sda_in = '0' then
                                    -- ACK received
                                    ack_recv    <= '1';
                                    rx_data_reg <= rx_shift;
                                    if stop_after = '1' then
                                        sda_drive <= '0';  -- SDA low for STOP
                                        state     <= ST_STOP_LOW;
                                    else
                                        sda_drive <= '1';
                                        state     <= ST_IDLE;
                                    end if;
                                else
                                    -- NACK — error, issue STOP
                                    error_flag <= '1';
                                    sda_drive  <= '0';
                                    state      <= ST_STOP_LOW;
                                end if;
                            else
                                -- Read mode: master already drove ACK/NACK
                                ack_recv    <= '1';
                                rx_data_reg <= rx_shift;
                                if stop_after = '1' then
                                    sda_drive <= '0';  -- SDA low for STOP
                                    state     <= ST_STOP_LOW;
                                else
                                    sda_drive <= '1';
                                    state     <= ST_IDLE;
                                end if;
                            end if;
                        end if;

                    -------------------------------------------------------
                    -- STOP_LOW: SCL low, SDA driven low — hold half-period.
                    -- On tick: release SCL (rising edge).
                    -------------------------------------------------------
                    when ST_STOP_LOW =>
                        if scl_tick = '1' then
                            scl_drive <= '1';  -- SCL rises
                            state     <= ST_STOP_HIGH;
                        end if;

                    -------------------------------------------------------
                    -- STOP_HIGH: SCL high, SDA still low — hold half-period.
                    -- On tick: release SDA (STOP condition), return to IDLE.
                    -------------------------------------------------------
                    when ST_STOP_HIGH =>
                        if scl_tick = '1' then
                            sda_drive   <= '1';  -- SDA rises = STOP condition
                            bus_claimed <= '0';
                            state       <= ST_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
