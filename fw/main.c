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
