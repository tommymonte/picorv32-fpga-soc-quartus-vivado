/* fw/i2c_driver.c — Bare-Metal I2C Driver */

#include "i2c_driver.h"

/* ── Private: poll until BUSY clears ──────────────────────────────────────── */
/*
 * Spins until STATUS.BUSY = 0.
 * Returns 0 on success (ACK received), -1 on error (NACK).
 *
 * In simulation the spin terminates as soon as the FSM finishes.
 * For real hardware, add a timeout counter to avoid infinite spin.
 */
static int wait_for_completion(void) {
    unsigned int status;

    do {
        status = I2C_STATUS;
    } while (status & I2C_STATUS_BUSY);

    if (status & I2C_STATUS_ERROR) {
        return -1;   /* NACK received */
    }

    return 0;        /* ACK received */
}

/* ── i2c_init ──────────────────────────────────────────────────────────────── */
/*
 * Clears the CTRL register to ensure no stale START/STOP bits remain
 * from a previous session or reset.
 */
void i2c_init(void) {
    I2C_CTRL = 0u;
}

/* ── i2c_write_byte ──────────────────────────────────────────────────────── */
/*
 * Writes one data byte to an I2C slave.
 *
 * Protocol sequence (multi-phase FSM, C-01 Option A):
 *   Phase 1 — Address:
 *     Write TX_DATA = (slave_addr << 1) | 0  (7-bit addr, W=0)
 *     Write CTRL    = EN | START              (triggers START + address TX)
 *     Poll STATUS.BUSY until clear            (address phase done)
 *   Phase 2 — Data:
 *     Write TX_DATA = data
 *     Write CTRL    = EN | STOP               (triggers data TX + STOP)
 *     Poll STATUS.BUSY until clear
 *
 * Parameters:
 *   slave_addr : 7-bit I2C slave address (not pre-shifted)
 *   data       : byte to write
 *
 * Returns:
 *    0 on success (both phases ACKed)
 *   -1 on NACK (slave absent or busy)
 */
int i2c_write_byte(unsigned char slave_addr, unsigned char data) {

    /* ── Phase 1: Address byte ─────────────────────────────────────────── */

    /* 7-bit address + W=0 in bits [7:0]:  addr<<1 with bit0=0 */
    I2C_TX_DATA = (unsigned int)(slave_addr << 1) & 0xFEu;

    /* Trigger START condition and address transmission */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_START;

    if (wait_for_completion() != 0) {
        I2C_CTRL = 0u;
        return -1;   /* NACK on address */
    }

    /* ── Phase 2: Data byte ────────────────────────────────────────────── */

    I2C_TX_DATA = (unsigned int)data;

    /* Transmit data then issue STOP */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_STOP;

    if (wait_for_completion() != 0) {
        I2C_CTRL = 0u;
        return -1;   /* NACK on data */
    }

    I2C_CTRL = 0u;
    return 0;
}

/* ── i2c_read_byte ───────────────────────────────────────────────────────── */
/*
 * Reads one byte from an I2C slave.
 *
 * Protocol sequence (multi-phase FSM, C-01 Option A):
 *   Phase 1 — Address with READ bit:
 *     Write TX_DATA = (slave_addr << 1) | 1  (7-bit addr, R=1)
 *     Write CTRL    = EN | START | RW         (triggers START + address TX)
 *     Poll STATUS.BUSY
 *   Phase 2 — Receive byte:
 *     Write CTRL    = EN | STOP | RW          (master receives 1 byte then STOP)
 *     Poll STATUS.BUSY
 *     Read RX_DATA
 *
 * Parameters:
 *   slave_addr : 7-bit I2C slave address
 *   data       : pointer to store the received byte (NULL-checked)
 *
 * Returns:
 *    0 on success
 *   -1 on NACK
 */
int i2c_read_byte(unsigned char slave_addr, unsigned char *data) {

    /* ── Phase 1: Address phase with READ bit ──────────────────────────── */

    /* 7-bit address + R=1 */
    I2C_TX_DATA = ((unsigned int)(slave_addr << 1)) | 0x01u;

    /* Trigger START; RW=1 so FSM knows it is the address for a read */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_START | I2C_CTRL_RW;

    if (wait_for_completion() != 0) {
        I2C_CTRL = 0u;
        return -1;   /* NACK on address */
    }

    /* ── Phase 2: Receive data byte ────────────────────────────────────── */

    /* Receive one byte; master sends NACK + STOP (stop_after=1 → NACK) */
    I2C_CTRL = I2C_CTRL_EN | I2C_CTRL_STOP | I2C_CTRL_RW;

    if (wait_for_completion() != 0) {
        I2C_CTRL = 0u;
        return -1;
    }

    /* Copy received byte to caller's buffer */
    if (data != (unsigned char *)0) {
        *data = (unsigned char)(I2C_RX_DATA & 0xFFu);
    }

    I2C_CTRL = 0u;
    return 0;
}
