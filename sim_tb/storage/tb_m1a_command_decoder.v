`timescale 1ns/1ps
`include "m1a_protocol.vh"

module tb_m1a_command_decoder;
    reg clk=0, rst_n=0, byte_valid=0, cmd_ready=1;
    reg [7:0] byte_data=0;
    wire byte_ready, cmd_valid, error_valid;
    wire [7:0] cmd_opcode, error_code;
    wire [31:0] cmd_arg;
    integer errors=0, checks=0;
    integer cmd_count=0, error_count=0;
    always #5 clk=~clk;

    m1a_command_decoder dut (
        .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .byte_data(byte_data),
        .byte_ready(byte_ready), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_opcode(cmd_opcode), .cmd_arg(cmd_arg), .error_valid(error_valid),
        .error_code(error_code)
    );

    always @(posedge clk) begin
        if (cmd_valid && cmd_ready) cmd_count = cmd_count + 1;
        if (error_valid) error_count = error_count + 1;
    end

    function [15:0] crc8;
        input [15:0] c0; input [7:0] d;
        reg [15:0] c; integer i;
        begin
            c=c0^{d,8'h00};
            for(i=0;i<8;i=i+1) if(c[15]) c={c[14:0],1'b0}^16'h1021; else c={c[14:0],1'b0};
            crc8=c;
        end
    endfunction

    task put; input [7:0] d; begin
        while(!byte_ready) @(posedge clk);
        @(negedge clk); byte_data=d; byte_valid=1;
        @(negedge clk); byte_valid=0;
    end endtask

    task command; input [7:0] op; input [31:0] arg; input integer n; input bad;
        reg [15:0] c; integer i;
        begin
            c=`M1A_CRC_INIT; put(`M1A_FRAME_SOF); put(op); c=crc8(c,op); put(n[7:0]); c=crc8(c,n[7:0]);
            for(i=n-1;i>=0;i=i-1) begin put(arg[i*8 +: 8]); c=crc8(c,arg[i*8 +: 8]); end
            put(c[15:8]); put(bad ? c[7:0]^8'h01 : c[7:0]);
            repeat(2) @(posedge clk);
        end
    endtask

    initial begin
        #20; rst_n=1;
        command(`M1A_CMD_OPEN,32'h00000002,1,0);
        checks=checks+1; if(cmd_count!=1 || cmd_opcode!=`M1A_CMD_OPEN || cmd_arg!=32'h2) begin $display("ERROR valid command"); errors=errors+1; end
        command(`M1A_CMD_CREDIT,32'h00000003,2,1);
        checks=checks+1; if(error_count!=1 || error_code!=`M1A_ERR_BAD_CRC) begin $display("ERROR bad crc"); errors=errors+1; end
        command(`M1A_CMD_CREDIT,32'h00000003,2,0);
        checks=checks+1; if(cmd_count!=2 || cmd_opcode!=`M1A_CMD_CREDIT || cmd_arg!=3) begin $display("ERROR credit command"); errors=errors+1; end
        if(errors==0) $display("PASS: m1a_command_decoder checks=%0d",checks); else $display("FAIL: %0d errors",errors);
        $finish;
    end
endmodule
