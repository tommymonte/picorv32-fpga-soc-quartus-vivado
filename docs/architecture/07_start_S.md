# `fw/start.S` — RISC-V Startup Code

## Role in the System

`start.S` is the **first code the CPU executes** after reset. PicoRV32 always begins execution at address `0x00000000` (the reset vector). This file:

1. Sets up the stack pointer (`sp` = `x2` register).
2. Zeroes the `.bss` section (uninitialized globals).
3. Jumps to `main()`.
4. Provides a trap loop at the bottom if `main()` ever returns.

Without this file, the C compiler's generated `main.c` code has no valid stack — function calls will crash.

---

## Why Assembly and Not C?

- C function calls require `sp` to be valid before the first instruction.
- `sp` cannot be set in C without a valid `sp` already set — chicken-and-egg.
- The linker script defines the stack location; this file reads that symbol and writes it into the `sp` register.

---

## Complete Implementation

```asm
# fw/start.S
# RISC-V RV32IMC startup code for PicoRV32 SoC
# Placed at 0x00000000 by the linker script.

.section .text.start   # Named section so link.ld can place it first
.global _start
.global main

_start:

    # ── 1. Set stack pointer ──────────────────────────────────────────────
    # _stack_top is defined in link.ld as the top of RAM (0x00004000 for 16 KB).
    # RISC-V stack grows downward; sp points to the first free location above data.
    la      sp, _stack_top          # Load address of stack top into sp (x2)

    # ── 2. Zero BSS section ───────────────────────────────────────────────
    # BSS: uninitialized global variables (e.g., int counter; with no initializer).
    # The C standard requires these to start at zero.
    # _bss_start and _bss_end are defined in link.ld.
    la      t0, _bss_start
    la      t1, _bss_end
    bge     t0, t1, bss_done        # Skip if BSS is empty

bss_loop:
    sw      zero, 0(t0)             # Store 32-bit zero at address t0
    addi    t0, t0, 4               # Advance by one word
    blt     t0, t1, bss_loop        # Loop until t0 >= t1

bss_done:

    # ── 3. Jump to main ───────────────────────────────────────────────────
    call    main                    # Jump-and-link to main(); ra (x1) = return addr

    # ── 4. Trap loop (if main returns) ────────────────────────────────────
    # main() should never return (infinite loop inside). If it does, hang here.
_halt:
    j       _halt
```

---

## Dependency on Linker Script

The symbols used in `start.S` must be defined in `link.ld`:

| Symbol | Defined in | Meaning |
|--------|-----------|---------|
| `_stack_top` | `link.ld` | Byte address just above end of RAM |
| `_bss_start` | `link.ld` | Start of `.bss` section |
| `_bss_end` | `link.ld` | End of `.bss` section |
| `main` | `main.c` | C entry point |

---

## Section Placement

The linker must place `.text.start` **before** any other code at `0x00000000`. In `link.ld`:

```ld
SECTIONS {
    . = 0x00000000;

    .text : {
        *(.text.start)    /* <-- start.S goes first */
        *(.text*)
        *(.rodata*)
    }
    ...
}
```

---

## Register Usage

| Register | ABI Name | Usage in start.S |
|----------|----------|------------------|
| `x2`     | `sp`     | Stack pointer — set to `_stack_top` |
| `x1`     | `ra`     | Return address — set by `call main` |
| `x5`     | `t0`     | Scratch: BSS loop pointer |
| `x6`     | `t1`     | Scratch: BSS end pointer |
| `x0`     | `zero`   | Always zero — used for BSS zeroing |

---

## Compilation

`start.S` is compiled as part of the firmware:

```bash
riscv64-unknown-elf-gcc \
    -march=rv32imc -mabi=ilp32 \
    -nostdlib \
    -T fw/link.ld \
    -o fw.elf \
    fw/start.S fw/main.c fw/i2c_driver.c
```

The `-nostdlib` flag tells GCC not to link the standard C runtime (`crt0.S`, `libc`). Our `start.S` replaces that entirely.

---

## Verifying with objdump

After compiling, inspect the output to confirm `_start` is at `0x00000000`:

```bash
riscv64-unknown-elf-objdump -d fw.elf | head -40
```

Expected output:
```
00000000 <_start>:
   0: 00004117   auipc  sp,0x4       # sp = PC + 0x4000 (loads _stack_top)
   4: 00010113   addi   sp,sp,0      # (offset may vary)
   ...
```

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Not zeroing BSS | Global variables have garbage values | Always zero BSS, even if you think you initialize everything |
| `_stack_top` not 4-byte aligned | Stack misalignment causes faults on some ABI ops | Ensure `link.ld` aligns stack to 16 bytes |
| Using `j main` instead of `call main` | `main()` cannot return (ra not set) | Use `call main`; then `_halt` loop handles return |
| Wrong section name (`.text` not `.text.start`) | Linker may not place startup code first | Use `.section .text.start` and pin it first in `link.ld` |
