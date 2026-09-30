`timescale 1ns/1ps
module tb_m1a_spi_slave;
    reg spi_clk=0, spi_cs_n=1, spi_mosi=0;
    reg [7:0] tx_data=8'hA6;
    wire spi_miso, tx_ready, rx_valid;
    wire [7:0] rx_data;
    integer errors=0,checks=0,i;
    reg [7:0] rx_sample;
    m1a_spi_slave dut(.spi_clk(spi_clk),.spi_cs_n(spi_cs_n),.spi_mosi(spi_mosi),.spi_miso(spi_miso),.tx_data(tx_data),.tx_ready(tx_ready),.rx_valid(rx_valid),.rx_data(rx_data));

    task transfer; input [7:0] master_byte; input [7:0] expected_slave; begin
        rx_sample=0; spi_cs_n=0; #2;
        for(i=7;i>=0;i=i-1) begin
            spi_mosi=master_byte[i]; #3; spi_clk=1; #1; rx_sample={rx_sample[6:0],spi_miso}; #2; spi_clk=0; #2;
        end
        spi_cs_n=1; #2;
        checks=checks+1; if(rx_data!==master_byte) begin $display("ERROR rx got %h expected %h",rx_data,master_byte); errors=errors+1; end
        checks=checks+1; if(rx_sample!==expected_slave) begin $display("ERROR miso got %h expected %h",rx_sample,expected_slave); errors=errors+1; end
    end endtask

    initial begin
        #1; spi_cs_n=0; #1; spi_cs_n=1; #1;
        transfer(8'h3C,8'hA6);
        tx_data=8'h59;
        transfer(8'hC3,8'h59);
        checks=checks+1; if(!tx_ready) begin $display("ERROR tx_ready"); errors=errors+1; end
        if(errors==0) $display("PASS: m1a_spi_slave checks=%0d",checks); else $display("FAIL: %0d errors",errors);
        $finish;
    end
endmodule
