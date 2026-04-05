# `rtl/i2c_controller.vhd` — I2C Master Controller

## Role in the System

This module implements a **memory-mapped I2C master controller**. The CPU configures it by writing to registers via the memory bus. The controller then autonomously drives the SCL and SDA lines to execute the I2C transaction while the CPU polls the STATUS register to detect completion.

---

## Entity Interface

```vhdl
entity i2c_controller is
    generic (
        SYS_CLK_HZ : integer := 25_000_000;  -- System clock frequency
        I2C_CLK_HZ : integer := 100_000       -- Target SCL frequency (standard mode)
    );
    port (
        clk   : in    std_logic;
        rst   : in    std_logic;

        -- Register bus interface (from mem_bus)
        addr  : in    std_logic_vector(1 downto 0);   -- Register select [3:2] of mem_addr
        wdata : in    std_logic_vector(7 downto 0);   -- 8-bit write data
        rdata : out   std_logic_vector(31 downto 0);  -- 32-bit read data (zero-padded)
        wen   : in    std_logic;                      -- Write enable
        ren   : in    std_logic;                      -- Read enable
        ready : out   std_logic;                      -- Register access complete (1 cycle)

        -- I2C bus (open-drain)
        scl   : inout std_logic;
        sda   : inout std_logic
    );
end entity i2c_controller;
```

---

## Register Map

| `addr[1:0]` | Offset | Name     | R/W | Bits | Description |
|-------------|--------|----------|-----|------|-------------|
| `00`        | `0x00` | CTRL     | W   | [3:0]| `[0]` EN — enable controller; `[1]` START — trigger START condition; `[2]` STOP — send STOP after transaction; `[3]` RW — `0`=write, `1`=read |
| `01`        | `0x04` | STATUS   | R   | [2:0]| `[0]` BUSY — transaction in progress; `[1]` ACK_RECV — slave ACKed last byte; `[2]` ERROR — no ACK received (NACK) |
| `10`        | `0x08` | TX_DATA  | W   | [7:0]| Byte to transmit (slave address + R/W, or data byte) |
| `11`        | `0x0C` | RX_DATA  | R   | [7:0]| Last byte received from slave |

> The CPU writes `TX_DATA`, then writes `CTRL` with `START=1` to kick off the transaction. It then polls `STATUS.BUSY` until it clears.

---

## SCL Clock Divider

The system clock (25 MHz) must be divided to produce 100 kHz SCL:

```
SCL half-period = SYS_CLK_HZ / (2 × I2C_CLK_HZ) = 25_000_000 / 200_000 = 125 cycles
```

Implement as a counter:

```vhdl
constant SCL_HALF : integer := SYS_CLK_HZ / (2 * I2C_CLK_HZ);  -- 125

signal clk_cnt  : integer range 0 to SCL_HALF - 1;
signal scl_tick : std_logic;   -- Pulses every half SCL period

process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' or clk_cnt = SCL_HALF - 1 then
            clk_cnt  <= 0;
            scl_tick <= '1';
        else
            clk_cnt  <= clk_cnt + 1;
            scl_tick <= '0';
        end if;
    end if;
end process;
```

The FSM advances on `scl_tick` pulses only — this is the clock enable for all I2C state transitions.

---

## FSM State Diagram

```
                   ┌──────────┐
           rst ───►│  IDLE    │◄─────────────────────────────┐
                   └────┬─────┘                              │
          CTRL.START=1  │                              done/STOP
                   ┌────▼─────┐
                   │  START   │  SDA: 1→0 while SCL high
                   └────┬─────┘
                        │ (scl_tick)
                   ┌────▼─────┐
                   │  ADDR    │  Shift out 8 bits of TX_DATA (slave addr + RW)
                   │  (8 bits)│  SCL toggles, SDA driven from shift register
                   └────┬─────┘
                        │ (after 8 bits)
                   ┌────▼─────┐
                   │ ACK_WAIT │  Release SDA (tristate), check SDA on rising SCL
                   └────┬─────┘
                        │ SDA==0 (ACK)       SDA==1 (NACK)
                   ┌────▼─────┐         ┌────▼─────┐
                   │  DATA    │         │  ERROR   │
                   │  (8 bits)│         │  IDLE    │
                   └────┬─────┘         └──────────┘
                        │ (after 8 bits)
                   ┌────▼─────┐
                   │ DATA_ACK │  Release SDA, check ACK again
                   └────┬─────┘
              ┌─────────┴─────────┐
         more bytes?          CTRL.STOP=1
              │                   │
         back to DATA        ┌────▼─────┐
                             │  STOP    │  SCL high, SDA: 0→1
                             └────┬─────┘
                                  │
                             back to IDLE
```

### FSM State Encoding

```vhdl
type i2c_state_t is (
    ST_IDLE,
    ST_START,
    ST_ADDR,
    ST_ACK_WAIT,
    ST_DATA,
    ST_DATA_ACK,
    ST_STOP,
    ST_ERROR
);

signal state : i2c_state_t;
```

---

## Shift Register for TX/RX

```vhdl
signal tx_shift : std_logic_vector(7 downto 0);  -- Loaded from TX_DATA, shifted out MSB-first
signal bit_cnt  : integer range 0 to 7;
signal rx_shift : std_logic_vector(7 downto 0);  -- Shifted in from SDA, MSB-first
```

On entry to `ST_ADDR` or `ST_DATA`: `tx_shift <= tx_data_reg`.
Each `scl_tick` in these states:
```vhdl
-- Shift out MSB
sda_out  <= tx_shift(7);
tx_shift <= tx_shift(6 downto 0) & '0';  -- shift left

-- Shift in (for reads)
rx_shift <= rx_shift(6 downto 0) & sda_in;  -- sample SDA
```

---

## Open-Drain Modeling

I2C is an open-drain bus. Both SCL and SDA:
- Are **driven low** by pulling to '0'.
- **Released** by outputting 'Z' (high-impedance); the pull-up resistor brings them high.

```vhdl
-- SCL open-drain driver
scl <= '0' when scl_drive = '0' else 'Z';

-- SDA open-drain driver  
sda <= '0' when sda_drive = '0' else 'Z';

-- SDA input (read from bus)
sda_in <= sda;
```

In simulation with no slave connected, `sda` will be `'Z'` when released. Treat `'Z'` as `'1'` (bus idle / NACK) in the FSM logic:

```vhdl
sda_in_resolved <= '1' when sda = 'Z' else sda;
```

---

## Register Access (Synchronous)

```vhdl
-- Write
process(clk)
begin
    if rising_edge(clk) then
        if wen = '1' then
            case addr is
                when "00" => ctrl_reg    <= wdata(3 downto 0);
                when "10" => tx_data_reg <= wdata;
                when others => null;
            end case;
        end if;
    end if;
end process;

-- Read (combinatorial to keep ready=1 in same cycle)
rdata <= x"000000" & status_reg when addr = "01" else
         x"000000" & rx_data_reg when addr = "11" else
         (others => '0');

ready <= wen or ren;  -- Register access always completes in 1 cycle
```

> The FSM runs independently. Register writes are instantaneous (one clock). The CPU does not need to wait for the I2C transaction to finish before the write returns — it polls `STATUS.BUSY`.

---

## Status Register

```vhdl
signal status_reg : std_logic_vector(7 downto 0);

status_reg(0) <= busy;      -- '1' when FSM is not in ST_IDLE
status_reg(1) <= ack_recv;  -- Latched when slave ACKed
status_reg(2) <= error;     -- Latched when NACK detected
status_reg(7 downto 3) <= (others => '0');

-- busy: derived from state
busy <= '0' when state = ST_IDLE else '1';
```

---

## I2C Protocol Timing (Standard Mode, 100 kHz)

```
SCL period = 10 µs (100 kHz)
SCL high   = 5 µs (minimum per spec: 4 µs)
SCL low    = 5 µs (minimum per spec: 4.7 µs)

START condition: SDA falls while SCL is HIGH
STOP condition:  SDA rises while SCL is HIGH
Data bits:       SDA changes while SCL is LOW; sampled on SCL rising edge
```

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Driving SDA/SCL as `out` instead of `inout` | Can't receive ACK, can't do clock stretching | Always `inout`; drive via tristate |
| Advancing FSM without `scl_tick` gate | FSM runs at 25 MHz instead of 100 kHz | Every state transition must be inside `if scl_tick = '1'` |
| Forgetting to release SDA before sampling ACK | ACK always reads '0' (self-pull) | Set `sda_drive = '1'` (tristate) before ACK sample cycle |
| SCL held low during START/STOP | Violates I2C protocol | START: SDA falls while SCL=HIGH; STOP: SDA rises while SCL=HIGH |
| `ready` not asserted for register reads | CPU hangs waiting for `mem_ready` | Always assert `ready` for register accesses (1 cycle) |
