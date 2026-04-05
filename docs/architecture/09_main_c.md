# `fw/main.c` — Main Firmware Application

## Role in the System

`main.c` is the **top-level C firmware** that runs on the PicoRV32 CPU. It demonstrates hardware/software co-design by exercising two memory-mapped peripherals:

1. **GPIO** at `0x2000_0000`: writes an incrementing counter (visible in waveforms).
2. **I2C Controller** at `0x1000_0000`: calls `i2c_write_byte()` to send data over I2C.

The file evolves in two phases:
- **Day 2 (minimal):** GPIO counter loop only — verifies CPU boot and memory bus.
- **Day 5 (full):** GPIO + I2C calls using the driver from `i2c_driver.c`.

---

## Phase 1: Minimal GPIO Loop (Day 2)

```c
/* fw/main.c — Phase 1: GPIO counter only */

/* Memory-mapped peripheral addresses */
#define GPIO_BASE   ((volatile unsigned int *)0x20000000u)

void main(void) {
    unsigned int counter = 0;

    while (1) {
        *GPIO_BASE = counter;    /* Write counter to GPIO output register */
        counter++;
        /* No delay — runs as fast as possible (~1 write per ~5 instructions) */
    }
}
```

### Why `volatile`?

Without `volatile`, the compiler assumes the write has no observable effect (no return value used) and **optimizes it away**. `volatile` tells the compiler: "this memory location has side effects — always perform the access."

### Why `unsigned int` not `uint32_t`?

For bare-metal RV32 with `-mabi=ilp32`, `unsigned int` is guaranteed 32-bit. `uint32_t` requires `<stdint.h>` which may pull in unwanted C library dependencies with `-nostdlib`. Both work; using `uint32_t` with an explicit `<stdint.h>` include is cleaner.

---

## Phase 2: Full SoC Firmware (Day 5)

```c
/* fw/main.c — Phase 2: GPIO + I2C */

#include "i2c_driver.h"

#define GPIO_BASE   ((volatile unsigned int *)0x20000000u)

/* Simulated sensor address (I2C slave at 0x50) */
#define SENSOR_ADDR 0x50u

void main(void) {
    unsigned int counter = 0;
    int result;

    /* Initialize I2C controller */
    i2c_init();

    while (1) {

        /* ── I2C transaction: send counter value to slave ──── */
        result = i2c_write_byte(SENSOR_ADDR, (unsigned char)(counter & 0xFF));

        if (result == 0) {
            /* Success: ACK received — write counter to GPIO */
            *GPIO_BASE = counter;
        } else {
            /* Error: NACK — write error code (0xDEAD) to GPIO */
            *GPIO_BASE = 0xDEADu;
        }

        counter++;
    }
}
```

---

## Bare-Metal Constraints

Because we compile with `-nostdlib`, the following **standard library functions are NOT available**:

| Unavailable | Alternative |
|-------------|-------------|
| `printf`, `puts` | Write to GPIO or a UART peripheral |
| `malloc`, `free` | Use static allocation only |
| `memset`, `memcpy` | Write your own inline versions if needed |
| `assert()` | Write directly to GPIO register as an error code |
| `<stdint.h>` types | Use explicit `unsigned int` (32-bit on ilp32) |

If you need `uint8_t` / `uint32_t`, add a minimal `<stdint.h>` compatible header:

```c
/* fw/types.h — minimal type definitions */
typedef unsigned char      uint8_t;
typedef unsigned short     uint16_t;
typedef unsigned int       uint32_t;
typedef signed   char      int8_t;
typedef signed   short     int16_t;
typedef signed   int       int32_t;
```

---

## Delay Loop (Optional)

For simulation, no delay is needed — waveforms capture every cycle. For hardware testing with an LED or scope, add a software delay:

```c
static void delay_ms(unsigned int ms) {
    /* 25 MHz clock → 25,000 cycles per ms */
    volatile unsigned int cycles = ms * 25000u;
    while (cycles--) {
        __asm__ volatile ("nop");
    }
}
```

> `volatile` on `cycles` prevents the compiler from optimizing the loop away. The `__asm__ volatile ("nop")` adds a guaranteed instruction to prevent further loop elimination.

---

## Interrupt Handling (Not Required for This Project)

PicoRV32 supports machine-mode interrupts (`mtvec`, `mstatus`). This project does **not** use interrupts — all I2C transactions are polled. If you add interrupt support later, you would need to add an interrupt handler in `start.S` and set `mtvec`.

---

## Verifying in Simulation

After compiling Phase 1, in `tb_top_soc.vhd` waveforms:

- Look for `mem_addr = 0x20000000` with `mem_wstrb = 1111` and `mem_wdata = 0x00000000`, then `0x00000001`, `0x00000002`, etc.
- This confirms the CPU is executing the `while(1)` loop correctly.

After compiling Phase 2, additionally look for:
- `mem_addr = 0x10000008` with `mem_wdata = 0xA0` (TX_DATA = slave address)
- `mem_addr = 0x10000000` with `mem_wdata = 0x03` (CTRL = EN | START)
- `mem_addr = 0x10000004` repeated reads (polling STATUS.BUSY)

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Missing `volatile` on peripheral pointers | Writes optimized away | Always `volatile` for memory-mapped I/O |
| Using `printf` without libc | Linker error: undefined `_write`, `_exit` | Use GPIO writes for debugging instead |
| Infinite loop with no observable output | Hard to debug | Always write something to GPIO so simulation is verifiable |
| Pointer cast without explicit `u` suffix on address | Signed integer literal — UB on truncation | Always use `0x20000000u` (unsigned) |
