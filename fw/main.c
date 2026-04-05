/* fw/main.c — Phase 1: GPIO counter only */

/* Memory-mapped peripheral addresses */
#define GPIO_BASE   ((volatile unsigned int *)0x20000000u)

void main(void) {
    unsigned int counter = 0;

    while (1) {
        *GPIO_BASE = counter;    /* Write counter to GPIO output register */
        counter++;
    }
}
