# `rtl/mem_bus.vhd` — Memory Bus / Address Decoder

## Role in the System

This module sits between the PicoRV32 CPU and all memory-mapped slaves. It is a **combinatorial address decoder** plus a **`mem_ready` multiplexer**. When the CPU asserts `mem_valid` with an address, this module:

1. Decodes which slave owns that address range.
2. Forwards the transaction (address, write data, write strobes) to that slave.
3. Returns the slave's `rdata` and `ready` back to the CPU.

---

## Entity Interface

```vhdl
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

        -- Slave: GPIO (optional, internal register)
        gpio_out  : out std_logic_vector(31 downto 0);

        -- Slave: I2C controller
        i2c_scl   : inout std_logic;
        i2c_sda   : inout std_logic
    );
end entity mem_bus;
```

> The on-chip RAM is instantiated **inside** `mem_bus` (not in top_soc), which keeps all address-decoding co-located with the memory instances.

---

## Address Decode Logic

Use the upper bits of `mem_addr` to select the slave. The ranges are:

| `mem_addr[31:16]` | `mem_addr[31:28]` | Slave         |
|-------------------|-------------------|---------------|
| `0x0000`          | `0x0`             | On-chip RAM   |
| `0x1000`          | `0x1`             | I2C Controller|
| `0x2000`          | `0x2`             | GPIO          |

Implement with a `case` or `when` on `mem_addr(31 downto 28)`:

```vhdl
-- Chip-select signals (combinatorial)
signal sel_ram  : std_logic;
signal sel_i2c  : std_logic;
signal sel_gpio : std_logic;

sel_ram  <= '1' when mem_addr(31 downto 28) = x"0" else '0';
sel_i2c  <= '1' when mem_addr(31 downto 28) = x"1" else '0';
sel_gpio <= '1' when mem_addr(31 downto 28) = x"2" else '0';
```

---

## On-Chip RAM Instantiation (inside mem_bus)

```vhdl
u_ram : entity work.onchip_ram
    port map (
        clk    => clk,
        addr   => mem_addr(13 downto 2),   -- word address: 14-bit → 16K words
        wdata  => mem_wdata,
        wstrb  => mem_wstrb,
        rdata  => ram_rdata,
        en     => sel_ram and mem_valid
    );
```

> The RAM needs only bits `[13:2]` of the address — bits `[1:0]` are always `00` for aligned 32-bit accesses, and bits `[31:14]` are decoded by the selector.

---

## I2C Controller Instantiation (inside mem_bus)

```vhdl
u_i2c : entity work.i2c_controller
    port map (
        clk    => clk,
        rst    => rst,
        addr   => mem_addr(3 downto 2),   -- 4 registers: offsets 0x00–0x0C → bits [3:2]
        wdata  => mem_wdata(7 downto 0),  -- 8-bit registers
        rdata  => i2c_rdata,
        wen    => sel_i2c and mem_valid and (or mem_wstrb),
        ren    => sel_i2c and mem_valid and (mem_wstrb = "0000"),
        ready  => i2c_ready,
        scl    => i2c_scl,
        sda    => i2c_sda
    );
```

---

## GPIO Register (inside mem_bus)

GPIO is simple enough to implement directly in `mem_bus` without a separate file:

```vhdl
-- GPIO register process
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            gpio_reg <= (others => '0');
        elsif sel_gpio = '1' and mem_valid = '1' and mem_wstrb /= "0000" then
            gpio_reg <= mem_wdata;
        end if;
    end if;
end process;

gpio_out <= gpio_reg;
```

---

## `mem_ready` and `mem_rdata` Mux

The CPU expects exactly one `mem_ready` pulse per transaction. Use a combinatorial mux:

```vhdl
-- mem_ready: each slave drives its own ready; OR them (only one can be active)
mem_ready <= (sel_ram  and ram_ready)
          or (sel_i2c  and i2c_ready)
          or (sel_gpio and mem_valid);   -- GPIO: always ready in same cycle

-- mem_rdata: mux read data from the selected slave
mem_rdata <= ram_rdata   when sel_ram  = '1' else
             i2c_rdata   when sel_i2c  = '1' else
             gpio_reg    when sel_gpio = '1' else
             (others => '0');
```

> For the GPIO case, `mem_ready` fires combinatorially in the same cycle as `mem_valid` — this is valid in the PicoRV32 native bus protocol.

---

## Timing Diagram

```
          _   _   _   _   _   _
clk      | |_| |_| |_| |_| |_|

mem_valid  ___XXXXXXXXXXXXXXXXX___
mem_addr   ___[ 0x0000_0010      ]___   RAM read
mem_wstrb  ___[ 0000             ]___   (read)

sel_ram    ___XXXXXXXXXXXXXXXXX___
ram_ready  _______XXXXXXXXXXXXXXX___   (1-cycle latency typical for altsyncram)
mem_ready  _______XXXXXXXXXXXXXXX___   (forwarded from ram_ready)
mem_rdata  _______[ valid data   ]___
```

---

## Internal Signal Summary

| Signal       | Width | Direction | Description                                |
|--------------|-------|-----------|--------------------------------------------|
| `sel_ram`    | 1     | internal  | RAM address range selected                 |
| `sel_i2c`    | 1     | internal  | I2C address range selected                 |
| `sel_gpio`   | 1     | internal  | GPIO address range selected                |
| `ram_rdata`  | 32    | internal  | RAM read data                              |
| `ram_ready`  | 1     | internal  | RAM transaction complete                   |
| `i2c_rdata`  | 32    | internal  | I2C register read data (zero-extended)     |
| `i2c_ready`  | 1     | internal  | I2C register access complete               |
| `gpio_reg`   | 32    | internal  | GPIO output latch                          |

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Using full 32-bit address for RAM port | Wastes resources, potential mismatch | Slice to `[13:2]` for word-addressed 16 KB |
| `mem_ready` not gated on `mem_valid` | Spurious ready pulses | Always AND ready with `mem_valid` or the slave's own valid gating |
| Multiple slaves raising `mem_ready` simultaneously | CPU sees garbage data | Ensure mutually exclusive `sel_*` signals |
| I2C ready fires before register write is stable | Write lost | Register writes should sample on rising edge with `wen` |
