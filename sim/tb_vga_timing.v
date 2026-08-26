`timescale 1ns/1ps

// ================================================================
// Testbench : tb_vga_timing
// Function  : Verify vga_timing for 640x480@60:
//             - de active pixels per frame == H_ACTIVE*V_ACTIVE
//             - hsync pulses per frame == V_TOTAL
//             - pixel_x / pixel_y in range while de=1
// Run from sim_tb:
//   vsim -c -do ../sim/run_vga_timing.do
// ================================================================

module tb_vga_timing;
    localparam CLK_PERIOD = 39.72;     // ~25.175 MHz pixel clock
    localparam H_ACTIVE   = 640;
    localparam V_ACTIVE   = 480;
    localparam H_TOTAL    = 800;
    localparam V_TOTAL    = 525;

    reg  clk_pix = 1'b0;
    reg  rst_n   = 1'b0;
    wire hs, vs, de;
    wire [11:0] pixel_x, pixel_y;

    vga_timing #(
        .H_ACTIVE(H_ACTIVE),
        .V_ACTIVE(V_ACTIVE)
    ) u_dut (
        .clk_pix (clk_pix),
        .rst_n   (rst_n),
        .hs      (hs),
        .vs      (vs),
        .de      (de),
        .pixel_x (pixel_x),
        .pixel_y (pixel_y)
    );

    always #(CLK_PERIOD/2.0) clk_pix = ~clk_pix;

    integer active_px;   // active pixels counted in current frame
    integer hs_count;    // hsync pulses in current frame
    integer frames;      // completed frames
    integer checks;      // number of checks performed
    integer errors;      // number of failed checks
    reg     prev_vs;
    reg     prev_hs;

    initial begin
        active_px = 0; hs_count = 0; frames = 0; checks = 0; errors = 0;
        prev_vs = 1'b0; prev_hs = 1'b0;
        rst_n = 1'b0;
        #(CLK_PERIOD*5);
        rst_n = 1'b1;
        while (frames < 3) @(posedge clk_pix);
        #(CLK_PERIOD*2);
        if (errors == 0)
            $display("PASS: vga_timing 640x480 timing OK (frames=%0d checks=%0d)",
                     frames, checks);
        else
            $display("FAIL: %0d checks failed", errors);
        $stop;
    end

    always @(posedge clk_pix) begin
        if (de) active_px = active_px + 1;
        if (hs && !prev_hs) hs_count = hs_count + 1;
        prev_hs <= hs;

        if (de) begin
            checks = checks + 1;
            if (pixel_x >= H_ACTIVE) begin
                $error("de=1 but pixel_x=%0d (>=%0d)", pixel_x, H_ACTIVE);
                errors = errors + 1;
            end
            if (pixel_y >= V_ACTIVE) begin
                $error("de=1 but pixel_y=%0d (>=%0d)", pixel_y, V_ACTIVE);
                errors = errors + 1;
            end
        end

        if (vs && !prev_vs) begin
            if (frames > 0) begin
                checks = checks + 1;
                if (active_px != H_ACTIVE*V_ACTIVE) begin
                    $error("frame %0d active_px=%0d expect %0d",
                           frames, active_px, H_ACTIVE*V_ACTIVE);
                    errors = errors + 1;
                end
                checks = checks + 1;
                if (hs_count != V_TOTAL) begin
                    $error("frame %0d hs_count=%0d expect %0d",
                           frames, hs_count, V_TOTAL);
                    errors = errors + 1;
                end
                $display("frame %0d: active_px=%0d hs=%0d",
                         frames, active_px, hs_count);
            end
            frames = frames + 1;
            active_px = 0;
            hs_count  = 0;
        end
        prev_vs <= vs;
    end

endmodule

