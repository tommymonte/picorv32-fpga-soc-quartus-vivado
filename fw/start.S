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
