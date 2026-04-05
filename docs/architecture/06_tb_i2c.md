# `tb/tb_i2c.vhd` — I2C Controller Testbench

## Role in the System

This testbench verifies `i2c_controller.vhd` **in isolation**, before integrating it into the full SoC. It:

1. Drives register writes (CTRL, TX_DATA) to simulate what the CPU firmware would do.
2. Models a minimal I2C slave that ACKs every byte.
3. Verifies SCL and SDA waveforms match the I2C protocol.

---

## Entity Interface

```vhdl
entity tb_i2c is
end entity tb_i2c;
```

---

## Architecture Overview

```vhdl
architecture sim of tb_i2c is

    -- DUT signals
    signal clk    : std_logic := '0';
    signal rst    : std_logic := '1';
    signal addr   : std_logic_vector(1 downto 0);
    signal wdata  : std_logic_vector(7 downto 0);
    signal rdata  : std_logic_vector(31 downto 0);
    signal wen    : std_logic := '0';
    signal ren    : std_logic := '0';
    signal ready  : std_logic;

    -- I2C bus
    signal scl    : std_logic;
    signal sda    : std_logic;

    -- Slave model signals
    signal slave_ack : std_logic := '1';  -- '1' = ACK (pull SDA low on bit 9)

    constant CLK_PERIOD : time := 40 ns;   -- 25 MHz system clock

begin
```

---

## DUT Instantiation

```vhdl
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

    -- I2C pull-ups
    scl <= 'H';
    sda <= 'H';

    -- Clock
    clk <= not clk after CLK_PERIOD / 2;
```

---

## Register Write Procedure

Create a local procedure to abstract register writes:

```vhdl
    -- Helper: write one register
    procedure reg_write (
        signal clk_s  : in  std_logic;
        signal addr_s : out std_logic_vector(1 downto 0);
        signal wdata_s: out std_logic_vector(7 downto 0);
        signal wen_s  : out std_logic;
        signal ready_s: in  std_logic;
        reg  : in std_logic_vector(1 downto 0);
        data : in std_logic_vector(7 downto 0)
    ) is
    begin
        addr_s  <= reg;
        wdata_s <= data;
        wen_s   <= '1';
        wait until rising_edge(clk_s);
        wait until ready_s = '1';
        wen_s   <= '0';
        wait until rising_edge(clk_s);
    end procedure;
```

---

## Stimulus Process: I2C Write Transaction

The main stimulus simulates firmware doing `i2c_write_byte(slave_addr=0x50, data=0xAB)`:

```vhdl
    stimulus : process
    begin
        -- 1. Hold reset
        rst <= '1';
        wait for 200 ns;
        rst <= '0';
        wait for 100 ns;

        -- 2. Write TX_DATA = slave address (0x50 << 1 | 0 = 0xA0, write bit)
        reg_write(clk, addr, wdata, wen, ready, "10", x"A0");

        -- 3. Write CTRL = EN | START (bits [1:0] = "11")
        reg_write(clk, addr, wdata, wen, ready, "00", x"03");

        -- 4. Poll STATUS.BUSY until clear
        poll_busy : loop
            addr <= "01";   -- STATUS register
            ren  <= '1';
            wait until rising_edge(clk);
            ren  <= '0';
            wait until rising_edge(clk);
            exit poll_busy when rdata(0) = '0';  -- BUSY cleared
        end loop;

        -- 5. Check ACK received
        addr <= "01";
        ren  <= '1';
        wait until rising_edge(clk);
        ren  <= '0';
        assert rdata(1) = '1' report "ACK not received!" severity error;

        -- 6. Write data byte (TX_DATA = 0xAB)
        reg_write(clk, addr, wdata, wen, ready, "10", x"AB");

        -- 7. Trigger another byte with STOP (CTRL = EN | STOP = 0x05)
        reg_write(clk, addr, wdata, wen, ready, "00", x"05");

        -- 8. Wait for BUSY to clear
        wait for 200 us;   -- Enough time for byte + STOP at 100 kHz

        assert false report "Stimulus complete" severity note;
        wait;
    end process;
```

---

## I2C Slave Model

A minimal slave that ACKs every byte. It monitors SCL/SDA and pulls SDA low on the 9th clock edge (ACK bit):

```vhdl
    i2c_slave : process
        variable bit_count : integer := 0;
        variable in_transaction : boolean := false;
    begin
        -- Wait for START condition: SDA falls while SCL is high
        wait until falling_edge(sda) and scl = '1';
        in_transaction := true;
        bit_count := 0;

        transaction_loop : loop
            -- Count 8 data bits (on SCL rising edge, SDA stable)
            for i in 1 to 8 loop
                wait until rising_edge(scl);
                bit_count := bit_count + 1;
            end loop;

            -- 9th clock = ACK: slave pulls SDA low
            wait until falling_edge(scl);
            sda <= '0';            -- ACK: drive SDA low
            wait until rising_edge(scl);
            wait until falling_edge(scl);
            sda <= 'Z';            -- Release SDA after ACK

            bit_count := 0;

            -- Check for STOP condition (SDA rises while SCL is high)
            -- or continue for next byte
            wait until rising_edge(scl);
            if sda = '1' then
                exit transaction_loop;  -- STOP detected
            end if;
        end loop;
    end process;
```

---

## Expected Waveform

At 100 kHz SCL, a single-byte write transaction takes:
- START: 1 SCL period
- Address byte: 8 SCL periods
- ACK: 1 SCL period
- Data byte: 8 SCL periods
- ACK: 1 SCL period
- STOP: 1 SCL period
- **Total: ~20 SCL periods = 200 µs at 100 kHz**

```
SCL    ‾‾‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|      <- 8 bits
SDA    ‾‾‾‾|   A7  |   A6  | ... |   A0  |   R/W |  ACK  |  ...
            ↑ START                                  ↑ SDA low
            SDA falls                                (slave drives)
            while SCL high
```

---

## Assertions to Add

```vhdl
-- After full transaction: ACK_RECV should be '1', ERROR should be '0'
assert rdata(1) = '1' report "ACK_RECV not set" severity error;
assert rdata(2) = '0' report "ERROR flag set unexpectedly" severity error;

-- SCL should never go high while SDA transitions (no glitch)
-- (This is hard to check automatically; verify visually in waveform)
```

---

## ModelSim Run Script (`sim/run_tb_i2c.tcl`)

```tcl
vlib work
vcom -2008 ../rtl/i2c_controller.vhd
vcom -2008 ../tb/tb_i2c.vhd
vsim work.tb_i2c

add wave -divider "Clock & Reset"
add wave /tb_i2c/clk
add wave /tb_i2c/rst

add wave -divider "Register Interface"
add wave -hex /tb_i2c/addr
add wave -hex /tb_i2c/wdata
add wave -hex /tb_i2c/rdata
add wave     /tb_i2c/wen
add wave     /tb_i2c/ren
add wave     /tb_i2c/ready

add wave -divider "I2C Bus"
add wave /tb_i2c/scl
add wave /tb_i2c/sda

add wave -divider "I2C FSM (internal)"
add wave /tb_i2c/u_dut/state

run 500 us
```

---

## Verification Checklist

- [ ] SCL toggles at ~100 kHz (10 µs period)
- [ ] START condition: SDA falls while SCL is HIGH
- [ ] 8 address bits transmitted MSB-first
- [ ] SDA released on 9th clock; slave pulls it low (ACK)
- [ ] `STATUS.ACK_RECV = '1'` after first byte
- [ ] Data byte transmitted MSB-first after ACK
- [ ] STOP condition: SDA rises while SCL is HIGH
- [ ] `STATUS.BUSY = '0'` after STOP
- [ ] `STATUS.ERROR = '0'` (no NACK)
