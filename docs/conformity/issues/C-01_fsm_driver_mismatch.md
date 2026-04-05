# C-01 — FSM/Driver Protocol Mismatch

**Severity:** Critical
**Status:** OPEN
**Affects:** `rtl/i2c_controller.vhd`, `fw/i2c_driver.c`
**Docs:** [04_i2c_controller.md](../../architecture/04_i2c_controller.md), [10_i2c_driver.md](../../architecture/10_i2c_driver.md)

---

## Description

The I2C FSM in doc 04 and the firmware driver in doc 10 describe incompatible transaction models.

### What doc 04 (FSM) says

The FSM executes a single continuous transaction from one START trigger:

```
IDLE → START → ADDR (8 bits) → ACK_WAIT → DATA (8 bits) → DATA_ACK → STOP → IDLE
```

`BUSY = '1'` throughout the entire sequence. It only clears when the FSM reaches `ST_IDLE` after STOP.

### What doc 10 (driver) says

`i2c_write_byte` treats address and data as two separate triggered phases:

```c
// Phase 1 — address
I2C_TX_DATA = (slave_addr << 1) & 0xFEu;
I2C_CTRL    = I2C_CTRL_EN | I2C_CTRL_START;
wait_for_completion();   // polls until BUSY = 0  ← FSM must reach IDLE here

// Phase 2 — data
I2C_TX_DATA = data;
I2C_CTRL    = I2C_CTRL_EN | I2C_CTRL_STOP;  // no START bit
wait_for_completion();   // polls until BUSY = 0
```

The sequence diagram in doc 10 confirms `BUSY=0` appears after the address ACK before the data phase begins. This requires the FSM to return to IDLE after `ST_ACK_WAIT`.

### Contradiction

Under the doc 04 FSM, writing `CTRL = EN|STOP` (no START) after the address phase would find the FSM still in `ST_DATA` or later — it would never re-trigger. The driver would hang in `wait_for_completion()` forever because BUSY was never asserted again after `I2C_CTRL = EN|STOP`.

---

## Root Cause

Doc 04 was written as a classic single-START I2C transaction. Doc 10 was written assuming a two-phase register-triggered model where the FSM parks in IDLE between bytes.

---

## Resolution Options

### Option A — Multi-phase FSM (matches driver as written)

Add an intermediate IDLE return after `ST_ACK_WAIT`. The FSM idles after each byte ACK and waits for a new write to CTRL to continue:

```
IDLE →(START)→ START → ADDR → ACK_WAIT →(ACK)→ IDLE
IDLE →(EN, no START, no STOP)→ DATA → DATA_ACK →(ACK)→ IDLE
IDLE →(EN | STOP)→ DATA → DATA_ACK → STOP → IDLE
```

**Pros:** Driver code in doc 10 works unchanged.
**Cons:** CTRL register semantics become more complex; FSM state diagram in doc 04 must be rewritten.

### Option B — Single-phase FSM (rewrite driver)

Keep the doc 04 FSM unchanged. Redesign the driver to load TX_DATA for both address and data before triggering:

```c
// Load address byte
I2C_TX_DATA = (slave_addr << 1) & 0xFEu;
I2C_CTRL    = I2C_CTRL_EN | I2C_CTRL_START;
wait_for_completion();   // waits for whole transaction (addr + data + STOP)
```

This requires the FSM to support a "payload FIFO" or a second TX register, or the protocol is limited to address-only transactions per trigger.

**Pros:** FSM stays simple.
**Cons:** Requires significant driver redesign; multi-byte writes become complex.

### Recommended Fix

**Option A** — update doc 04 FSM to return to IDLE after each ACK, and update the state diagram accordingly. The driver in doc 10 is already correct for this model.

---

## Files to Update After Fix

- [04_i2c_controller.md](../../architecture/04_i2c_controller.md) — FSM state diagram and state encoding
- [06_tb_i2c.md](../../architecture/06_tb_i2c.md) — stimulus process timing (poll loop between phases)
