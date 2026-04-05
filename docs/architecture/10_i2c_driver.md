# `fw/i2c_driver.h` and `fw/i2c_driver.c` — Bare-Metal I2C Driver

## Role in the System

These files form the **software half of the hardware/software co-design**. The C driver translates high-level I2C operations (`i2c_write_byte`) into a sequence of memory-mapped register accesses that control `i2c_controller.vhd`.

This is the key integration artifact that demonstrates bare-metal embedded programming against a custom peripheral.

---

## Register Definitions (Match Hardware Exactly)

The register offsets must match `i2c_controller.vhd`'s register map:

```c
/* fw/i2c_driver.h */

#ifndef I2C_DRIVER_H
#define I2C_DRIVER_H

/* Base address of I2C controller in SoC memory map */
#define I2C_BASE    0x10000000u

/* Register addresses (base + offset) */
#define I2C_CTRL    (*(volatile unsigned int *)(I2C_BASE + 0x00u))
#define I2C_STATUS  (*(volatile unsigned int *)(I2C_BASE + 0x04u))
#define I2C_TX_DATA (*(volatile unsigned int *)(I2C_BASE + 0x08u))
#define I2C_RX_DATA (*(volatile unsigned int *)(I2C_BASE + 0x0Cu))

/* CTRL register bit definitions */
#define I2C_CTRL_EN     (1u << 0)   /* Enable controller */
#define I2C_CTRL_START  (1u << 1)   /* Issue START condition */
#define I2C_CTRL_STOP   (1u << 2)   /* Issue STOP after transaction */
#define I2C_CTRL_RW     (1u << 3)   /* 0=write, 1=read */

/* STATUS register bit definitions */
#define I2C_STATUS_BUSY     (1u << 0)   /* Transaction in progress */
#define I2C_STATUS_ACK_RECV (1u << 1)   /* Slave ACKed last byte */
#define I2C_STATUS_ERROR    (1u << 2)   /* NACK received (error) */

/* API */
void i2c_init(void);
int  i2c_write_byte(unsigned char slave_addr, unsigned char data);
int  i2c_read_byte(unsigned char slave_addr, unsigned char *data);

#endif /* I2C_DRIVER_H */
```

---

## Implementation

```c
/* fw/i2c_driver.c */

#include "i2c_driver.h"

/* ── Private: poll until BUSY clears ──────────────────────────────────── */
/*
 * Spins until STATUS.BUSY = 0.
 * Returns 0 on success (ACK received), -1 on error (NACK or timeout).
 *
 * In a real system, add a timeout counter to avoid infinite spin.
 * For simulation, the spin terminates as soon as the FSM finishes.
 */
static int wait_for_completion(void) {
    unsigned int status;

    /* Poll BUSY flag */
    do {
        status = I2C_STATUS;
    } while (status & I2C_STATUS_BUSY);

    /* Check for error (NACK) */
    if (status & I2C_STATUS_ERROR) {
        return -1;   /* NACK received — slave not present or not ready */
    }

    return 0;        /* ACK received */
}

/* ── i2c_init ─────────────────────────────────────────────────────────── */
/*
 * Initializes the I2C controller.
 * Clears the CTRL register to ensure no stale START/STOP bits.
 */
void i2c_init(void) {
    I2C_CTRL = 0u;      /* Reset all control bits */
}

/* ── i2c_write_byte ──────────────────────────────────────────────────── */
/*
 * Writes one byte to an I2C slave.
 *
 * Protocol sequence:
 *   1. Write slave address (7-bit) + W bit (0) into TX_DATA.
 *   2. Assert START → controller issues START + transmits TX_DATA.
 *   3. Wait for BUSY=0 (ACK for address phase).
 *   4. Write data byte into TX_DATA.
 *   5. Assert STOP → controller transmits TX_DATA then issues STOP.
 *   6. Wait for BUSY=0.
 *
 * Parameters:
 *   slave_addr : 7-bit I2C slave address (NOT shifted — driver shifts it)
 *   data       : data byte to write
 *
 * Returns:
 *    0 on success
 *   -1 on NACK (slave did not acknowledge)
 */
int i2c_write_byte(unsigned char slave_addr, unsigned char data) {

    /* ── Phase 1: Address byte ─────────────────────────────── */

    /* Construct 7-bit address + W=0 in the 8-bit TX_DATA field:
     * Bit 7..1 = slave_addr, Bit 0 = 0 (write) */
    I2C_TX_DATA = (unsigned int)(slave_addr << 1) & 0xFEu;  /* R/W=0 */

    /* Trigger START condition + address transmission */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_START;

    /* Wait for address byte to complete */
    if (wait_for_completion() != 0) {
        /* NACK on address — slave not present */
        I2C_CTRL = 0u;   /* Abort */
        return -1;
    }

    /* ── Phase 2: Data byte ────────────────────────────────── */

    I2C_TX_DATA = (unsigned int)data;

    /* Transmit data byte and then issue STOP */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_STOP;

    /* Wait for data byte + STOP to complete */
    if (wait_for_completion() != 0) {
        /* NACK on data */
        I2C_CTRL = 0u;
        return -1;
    }

    /* Clear control register */
    I2C_CTRL = 0u;
    return 0;
}

/* ── i2c_read_byte ───────────────────────────────────────────────────── */
/*
 * Reads one byte from an I2C slave.
 *
 * Protocol sequence:
 *   1. Write slave address + R bit (1) into TX_DATA.
 *   2. Assert START | RW → controller issues START + transmits address.
 *   3. Wait for BUSY=0 (ACK for address).
 *   4. Assert STOP | RW → controller receives one byte then issues STOP.
 *   5. Wait for BUSY=0.
 *   6. Read received byte from RX_DATA.
 *
 * Parameters:
 *   slave_addr : 7-bit I2C slave address
 *   data       : pointer to store received byte
 *
 * Returns:
 *    0 on success
 *   -1 on NACK
 */
int i2c_read_byte(unsigned char slave_addr, unsigned char *data) {

    /* ── Phase 1: Address phase (with READ bit) ─────────────── */

    /* 7-bit addr + R=1 */
    I2C_TX_DATA = ((unsigned int)(slave_addr << 1) | 0x01u);

    /* Trigger START + set RW=1 (read) */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_START | I2C_CTRL_RW;

    if (wait_for_completion() != 0) {
        I2C_CTRL = 0u;
        return -1;
    }

    /* ── Phase 2: Receive data byte ─────────────────────────── */

    /* Trigger receive: STOP after one byte */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_STOP | I2C_CTRL_RW;

    if (wait_for_completion() != 0) {
        I2C_CTRL = 0u;
        return -1;
    }

    /* Retrieve received byte */
    if (data != (unsigned char *)0) {
        *data = (unsigned char)(I2C_RX_DATA & 0xFFu);
    }

    I2C_CTRL = 0u;
    return 0;
}
```

---

## Interaction with Hardware (Sequence Diagram)

```
CPU (firmware)                         i2c_controller.vhd
─────────────────                      ──────────────────
Write TX_DATA = 0xA0  ──► 0x10000008 ─►  tx_data_reg ← 0xA0
Write CTRL = 0x03     ──► 0x10000000 ─►  CTRL ← EN|START
                                          FSM: IDLE → START → ADDR
                                          SCL/SDA begin toggling...
poll STATUS (addr 0x04) ◄── 0x10000004 ◄──  status_reg = BUSY=1
poll STATUS (addr 0x04) ◄── 0x10000004 ◄──  status_reg = BUSY=1
                                          FSM: ... → ACK_WAIT → ...
poll STATUS (addr 0x04) ◄── 0x10000004 ◄──  status_reg = BUSY=0, ACK=1
wait_for_completion returns 0

Write TX_DATA = 0xAB  ──► 0x10000008 ─►  tx_data_reg ← 0xAB
Write CTRL = 0x05     ──► 0x10000000 ─►  CTRL ← EN|STOP
                                          FSM: DATA → DATA_ACK → STOP → IDLE
poll STATUS ...
wait_for_completion returns 0
i2c_write_byte returns 0
```

---

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Not shifting slave address | Wrong 8-bit frame: bit 0 is garbled | Always `(addr << 1) | rw_bit` |
| Not waiting for BUSY before next write | Second transaction overwrites first mid-flight | Always call `wait_for_completion()` between phases |
| Reading STATUS before writing CTRL | Reads stale BUSY=0, skips polling loop | Write CTRL first, then poll |
| No timeout in `wait_for_completion` | Hangs forever if hardware broken | Add cycle counter; return -1 on timeout |
| `data` pointer not checked for NULL | Null dereference crash | Guard with `if (data != NULL)` |
