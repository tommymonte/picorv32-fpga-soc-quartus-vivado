# artix7.xdc — Vivado Constraint File for VGA Controller Port
# Target: Artix-7 xc7a35tcpg236-1 (Digilent Basys3)
# Replaces the Quartus .sdc file from the original Cyclone V project.

# ── Clock ─────────────────────────────────────────────────────────────────────
# 100 MHz oscillator on pin W5 (Basys3 schematic)
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz]
set_property PACKAGE_PIN W5      [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]

# ── Reset (BTN0) ───────────────────────────────────────────────────────────────
set_property PACKAGE_PIN U18     [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

# ── VGA Sync ───────────────────────────────────────────────────────────────────
set_property PACKAGE_PIN P19     [get_ports hsync]
set_property IOSTANDARD LVCMOS33 [get_ports hsync]

set_property PACKAGE_PIN R19     [get_ports vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vsync]

# ── VGA Red channel (4 bits) ───────────────────────────────────────────────────
set_property PACKAGE_PIN N19     [get_ports {vga_r[0]}]
set_property PACKAGE_PIN J19     [get_ports {vga_r[1]}]
set_property PACKAGE_PIN H19     [get_ports {vga_r[2]}]
set_property PACKAGE_PIN G19     [get_ports {vga_r[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

# ── VGA Green channel ──────────────────────────────────────────────────────────
set_property PACKAGE_PIN F19     [get_ports {vga_g[0]}]
set_property PACKAGE_PIN E19     [get_ports {vga_g[1]}]
set_property PACKAGE_PIN E20     [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D20     [get_ports {vga_g[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

# ── VGA Blue channel ───────────────────────────────────────────────────────────
set_property PACKAGE_PIN C20     [get_ports {vga_b[0]}]
set_property PACKAGE_PIN B20     [get_ports {vga_b[1]}]
set_property PACKAGE_PIN A20     [get_ports {vga_b[2]}]
set_property PACKAGE_PIN B19     [get_ports {vga_b[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

# ── False paths on asynchronous reset ─────────────────────────────────────────
# The reset input is a push-button (asynchronous to clock domain).
set_false_path -from [get_ports reset]
