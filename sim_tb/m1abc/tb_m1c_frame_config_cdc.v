`timescale 1ns/1ps
module tb_m1c_frame_config_cdc;
    reg src_clk = 1'b0;
    reg pix_clk = 1'b0;
    reg src_rst_n = 1'b0;
    reg pix_rst_n = 1'b0;
    reg [7:0] src_value = 8'd0;
    reg src_toggle = 1'b0;
    reg frame_boundary = 1'b0;
    wire [7:0] active_value;
    wire update_pulse;

    always #10 src_clk = ~src_clk;      // 50 MHz
    always #20 pix_clk = ~pix_clk;      // 25 MHz

    m1c_frame_config_cdc #(.WIDTH(8)) dut (
        .src_clk(src_clk), .src_rst_n(src_rst_n),
        .src_value(src_value), .src_update_toggle(src_toggle),
        .pix_clk(pix_clk), .pix_rst_n(pix_rst_n),
        .frame_boundary(frame_boundary), .active_value(active_value),
        .update_pulse(update_pulse));

    integer errors = 0;

    task pix_boundary;
        begin
            @(negedge pix_clk);
            frame_boundary = 1'b1;
            @(negedge pix_clk);
            frame_boundary = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge src_clk);
        src_rst_n = 1'b1;
        pix_rst_n = 1'b1;

        // Publish config 2. It must not become active merely because it
        // crossed the CDC; only a frame boundary may commit it.
        @(negedge src_clk);
        src_value = 8'd2;
        src_toggle = ~src_toggle;
        repeat (8) @(posedge pix_clk);
        if (active_value !== 8'd0) begin
            $display("ERROR: config changed before frame boundary: %0d", active_value);
            errors = errors + 1;
        end
        pix_boundary();
        repeat (2) @(posedge pix_clk);
        if (active_value !== 8'd2) begin
            $display("ERROR: config 2 not committed at frame boundary: %0d", active_value);
            errors = errors + 1;
        end

        // Publish config 3 and prove one more boundary-atomic update.
        @(negedge src_clk);
        src_value = 8'd3;
        src_toggle = ~src_toggle;
        repeat (8) @(posedge pix_clk);
        if (active_value !== 8'd2) begin
            $display("ERROR: config 3 leaked before frame boundary: %0d", active_value);
            errors = errors + 1;
        end
        pix_boundary();
        repeat (2) @(posedge pix_clk);
        if (active_value !== 8'd3) begin
            $display("ERROR: config 3 not committed: %0d", active_value);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: M1C frame-boundary configuration CDC");
        else
            $display("FAIL: M1C frame config CDC errors=%0d", errors);
        $finish;
    end
endmodule
