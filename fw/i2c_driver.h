/* fw/i2c_driver.h — Bare-Metal I2C Driver Header */

#ifndef I2C_DRIVER_H
#define I2C_DRIVER_H

/* Base address of I2C controller in SoC memory map */
#define I2C_BASE    0x10000000u

/* Register addresses (base + byte offset) */
#define I2C_CTRL    (*(volatile unsigned int *)(I2C_BASE + 0x00u))
#define I2C_STATUS  (*(volatile unsigned int *)(I2C_BASE + 0x04u))
#define I2C_TX_DATA (*(volatile unsigned int *)(I2C_BASE + 0x08u))
#define I2C_RX_DATA (*(volatile unsigned int *)(I2C_BASE + 0x0Cu))

/* CTRL register bit definitions */
#define I2C_CTRL_EN     (1u << 0)   /* Enable: kick off the current phase */
#define I2C_CTRL_START  (1u << 1)   /* Issue START condition before this byte */
#define I2C_CTRL_STOP   (1u << 2)   /* Issue STOP after this byte */
#define I2C_CTRL_RW     (1u << 3)   /* 0 = write (master TX), 1 = read (master RX) */

/* STATUS register bit definitions */
#define I2C_STATUS_BUSY     (1u << 0)   /* FSM active — transaction in progress */
#define I2C_STATUS_ACK_RECV (1u << 1)   /* Slave ACKed the last byte */
#define I2C_STATUS_ERROR    (1u << 2)   /* NACK received (slave not present / not ready) */

/* API */
void i2c_init(void);
int  i2c_write_byte(unsigned char slave_addr, unsigned char data);
int  i2c_read_byte(unsigned char slave_addr, unsigned char *data);

#endif /* I2C_DRIVER_H */
