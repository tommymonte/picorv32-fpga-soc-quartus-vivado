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

    /* ── Initialized data ────────────────────────────────────── */
    /* No flash in this SoC — .mif pre-loads everything into RAM */
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
