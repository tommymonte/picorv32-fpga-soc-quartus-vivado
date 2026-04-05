# `fw/link.ld` — Linker Script

## Role in the System

The linker script tells the linker (`riscv64-unknown-elf-ld`) **where to place each section** of the compiled firmware in the address space. Without it, the linker would put code at some default address that does not match the FPGA memory map.

For this SoC, the rules are:
- All code and data lives in the on-chip RAM at `0x00000000–0x00003FFF` (16 KB).
- The reset vector is at `0x00000000` — `_start` must be the very first byte.
- The stack grows downward from `0x00004000` (top of RAM).

---

## Complete Implementation

```ld
/* fw/link.ld — Linker script for PicoRV32 SoC (16 KB on-chip RAM) */

OUTPUT_ARCH(riscv)
ENTRY(_start)           /* Reset vector: _start in start.S */

MEMORY {
    /*
     * Single memory region: 16 KB on-chip RAM
     * Base: 0x00000000  (matches SoC memory map)
     * Length: 16K = 0x4000 bytes
     */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS {

    /* ── Code and read-only data ─────────────────────────────── */
    .text ORIGIN(RAM) : {
        KEEP(*(.text.start))    /* start.S must be first — reset vector */
        *(.text*)               /* All other code */
        *(.rodata*)             /* String literals, const arrays */
        . = ALIGN(4);           /* Pad to 4-byte boundary */
        _text_end = .;
    } > RAM

    /* ── Initialized data (copied from flash in real systems) ─── */
    /* In this SoC: everything is in RAM, no separate flash/ROM.   */
    /* Data is initialized directly in the .mif file.             */
    .data : {
        _data_start = .;
        *(.data*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM

    /* ── Uninitialized data (zeroed by start.S) ──────────────── */
    .bss : {
        _bss_start = .;         /* start.S reads this symbol */
        *(.bss*)
        *(COMMON)               /* Old-style common symbols */
        . = ALIGN(4);
        _bss_end = .;           /* start.S reads this symbol */
    } > RAM

    /* ── Stack ───────────────────────────────────────────────── */
    /* Stack is NOT a section — it lives in the remaining RAM.    */
    /* _stack_top is set to end of RAM; start.S loads this.       */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);    /* 0x00004000 */

    /* ── Sanity check: crash if firmware exceeds RAM ─────────── */
    ASSERT((_bss_end <= _stack_top - 256),
        "ERROR: Firmware too large — overflows RAM (leaves < 256 bytes for stack)")

}
```

---

## Memory Layout Visualization

```
Address         Content
─────────────────────────────────────────────
0x00000000  ←── _start (reset vector)
            │   .text.start   (start.S)
            │   .text*        (main.c, i2c_driver.c compiled code)
            │   .rodata*      (const data, string literals)
            ├── _text_end
            │   .data*        (initialized globals)
            ├── _data_end, _bss_start
            │   .bss*         (uninitialized globals → zeroed by start.S)
            ├── _bss_end
            │   [unused RAM]
            │   [grows ↓]
0x00004000  ←── _stack_top (sp initialized here; stack grows downward)
```

---

## Key Symbols Exported to start.S

| Symbol | Value | Used by |
|--------|-------|---------|
| `_start` | `0x00000000` | CPU reset vector |
| `_bss_start` | End of `.data` | `start.S` BSS zeroing loop |
| `_bss_end` | End of `.bss` | `start.S` BSS zeroing loop |
| `_stack_top` | `0x00004000` | `start.S` stack pointer init |

---

## Why `KEEP(*(.text.start))`

The `KEEP()` directive tells the linker not to discard this section even if it appears unused. Without `KEEP`, the linker might optimize away `_start` if it doesn't see any references to it (which is the case since the CPU jumps to it via hardware, not via a linker reference).

---

## Why No `.data` Initialization Code

In typical embedded systems, `.data` (initialized globals) lives in ROM (flash) and gets copied to RAM on startup. This SoC has no flash — the `.mif` file pre-loads the entire RAM contents including initialized data. So there is no copy loop needed in `start.S`.

However, if you add a `static int x = 5;` global, the linker will place `5` in the `.data` section, and `bin2mif.py` will include it in the `.mif` at the correct offset.

---

## Verifying the Layout

After compiling:

```bash
# Show section layout with addresses and sizes
riscv64-unknown-elf-size -A fw.elf

# Show exact addresses of key symbols
riscv64-unknown-elf-nm fw.elf | grep -E "_start|_bss|_stack"
```

Expected output:
```
00000000 T _start
00000xxx T _bss_start
00000yyy T _bss_end
00004000 A _stack_top
```

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| `ORIGIN = 0x00000000` missing | Code placed at wrong address | Always specify ORIGIN explicitly |
| Forgetting `KEEP(.text.start)` | `_start` may be garbage-collected | Use `KEEP()` on the startup section |
| Stack too small (BSS + data close to 0x4000) | Stack overflow at runtime (silent corruption) | Check `riscv64-unknown-elf-size -A fw.elf`; keep at least 512 B free |
| No `ALIGN(4)` between sections | BSS zeroing loop accesses unaligned addresses | Always align section ends to 4 bytes |
| `OUTPUT_ARCH(riscv)` missing | Linker may produce wrong ELF format | Include it |
