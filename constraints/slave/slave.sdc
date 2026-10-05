create_clock -name clk50m -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
# Each input crosses through its explicit two-flop level synchronizer.
set_false_path -from [get_ports {link_ack display_published}]
# Source registers hold data through the full acknowledged request transaction.
set_max_delay 40.000 -to [get_ports {link_data[*] link_req}]
