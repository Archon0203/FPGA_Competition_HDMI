# Standalone M1A fit estimate only; clocks model the validation harness.
create_clock -name m1a_service_clk -period 20.000 [get_ports {service_clk}]
create_clock -name m1a_provider_clk -period 20.000 [get_ports {provider_clk}]
create_clock -name m1a_spi_clk -period 100.000 [get_ports {spi_clk}]
set_clock_groups -asynchronous \
    -group [get_clocks {m1a_service_clk}] \
    -group [get_clocks {m1a_provider_clk}] \
    -group [get_clocks {m1a_spi_clk}]
