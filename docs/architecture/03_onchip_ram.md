# `rtl/onchip_ram.vhd` — On-Chip RAM (16 KB)

## Role in the System

This module provides the **program memory** and **data memory** for the PicoRV32 CPU. On reset, it contains the compiled firmware image loaded from a `.mif` file. It is a single-port synchronous RAM built on Intel's `altsyncram` megafunction.

---

## Entity Interface

```vhdl
entity onchip_ram is
    generic (
        ADDR_WIDTH : integer := 12;    -- 2^12 = 4096 words × 4 bytes = 16 KB
        MIF_FILE   : string  := "fw.mif"
    );
    port (
        clk   : in  std_logic;
        en    : in  std_logic;                        -- Enable (= sel_ram AND mem_valid)
        addr  : in  std_logic_vector(11 downto 0);   -- Word address [13:2] from mem_addr
        wdata : in  std_logic_vector(31 downto 0);   -- Write data
        wstrb : in  std_logic_vector( 3 downto 0);   -- Byte enables
        rdata : out std_logic_vector(31 downto 0);   -- Read data (registered, 1-cycle latency)
        ready : out std_logic                        -- Transaction complete
    );
end entity onchip_ram;
```

---

## Memory Geometry

| Parameter | Value |
|-----------|-------|
| Capacity  | 16,384 bytes = 16 KB |
| Word width | 32 bits (4 bytes) |
| Number of words | 4,096 (0x0000–0x0FFF word addresses) |
| Address bits | 12 (`2^12 = 4096`) |
| Address from CPU | `mem_addr[13:2]` (byte address ÷ 4) |

---

## altsyncram Instantiation

Use a `component` instantiation of the Quartus-generated `altsyncram` megafunction. The key parameters:

```vhdl
component altsyncram
    generic (
        operation_mode         => "SINGLE_PORT",
        width_a                => 32,
        widthad_a              => 12,        -- 12-bit address → 4K words
        numwords_a             => 4096,
        init_file              => "fw.mif",  -- Firmware pre-loaded at power-on
        init_file_layout       => "PORT_A",
        outdata_reg_a          => "UNREGISTERED",  -- Combinatorial output (or "CLOCK0" for registered)
        byte_size              => 8,
        width_byteena_a        => 4
    );
    port (
        clock0    : in  std_logic;
        address_a : in  std_logic_vector(11 downto 0);
        data_a    : in  std_logic_vector(31 downto 0);
        wren_a    : in  std_logic;
        byteena_a : in  std_logic_vector( 3 downto 0);
        q_a       : out std_logic_vector(31 downto 0)
    );
end component;
```

> **`outdata_reg_a`**: If set to `"UNREGISTERED"`, output is combinatorial (no clock latency on read). If set to `"CLOCK0"`, output is registered (1-cycle read latency). The `ready` signal behavior must match this choice — see below.

---

## Read Latency and `ready` Signal

### Option A: Unregistered Output (simpler, fewer cycles)

```vhdl
-- Output is combinatorial, so ready fires in the same cycle
ready <= en;    -- Immediately ready when enabled
```

PicoRV32 can accept `mem_ready` in the same cycle as `mem_valid`.

### Option B: Registered Output (typical for `altsyncram` defaults)

```vhdl
-- Output appears one clock after the address is presented
-- Delay ready by one cycle:
process(clk)
begin
    if rising_edge(clk) then
        ready <= en;    -- ready is high one cycle after en
    end if;
end process;
```

> **Recommendation:** Use `outdata_reg_a = "UNREGISTERED"` for simplicity. Registered output requires the CPU to accept zero-wait-state pipelining, which PicoRV32 does support but adds complexity to verify.

---

## Write Behavior

`altsyncram` supports byte-enable writes when `byte_size = 8` and `width_byteena_a = 4`:

```
wren_a    = '1' when any byte of wstrb is set: wren_a <= (or wstrb)
byteena_a = wstrb
data_a    = wdata
```

The logic for driving these:

```vhdl
wren_a    <= en and (wstrb(3) or wstrb(2) or wstrb(1) or wstrb(0));
byteena_a <= wstrb;
```

---

## .mif File Format

The Makefile generates `fw.mif` from `fw.bin` using `bin2mif.py`. The format looks like:

```
DEPTH = 4096;
WIDTH = 32;
ADDRESS_RADIX = HEX;
DATA_RADIX = HEX;

CONTENT BEGIN
  0000 : 00000093;   -- addi x1, x0, 0
  0001 : 00000113;   -- addi x2, x0, 0
  ...
  3FFF : 00000000;   -- padding
END;
```

Important: Quartus reads the `.mif` file at **synthesis/elaboration time** to initialize the M10K blocks. When you change the firmware, you must re-run synthesis (or at minimum re-assemble the netlist) to load the new `.mif`.

---

## Wiring to `mem_bus`

In `mem_bus.vhd`, the RAM is wired like this:

```vhdl
-- Address: strip byte-address bits [1:0] and range-select bits [31:14]
ram_addr <= mem_addr(13 downto 2);

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
```

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Wrong `init_file` path in generic | RAM starts with zeros; CPU executes NOP sled and hangs | Use relative path from Quartus project directory |
| `ADDR_WIDTH = 14` (byte address) instead of `12` | Address maps to wrong word | Always use word address: `ADDR_WIDTH = 12` |
| `wren_a` tied high | Every read also does a write | Gate wren with `(or wstrb)` |
| Endianness mismatch in `.mif` | Instructions execute as garbage | Verify `bin2mif.py` outputs little-endian 32-bit words |
| Registered output but `ready` tied to `en` combinatorially | CPU latches stale data | Match `ready` timing to `outdata_reg_a` setting |
