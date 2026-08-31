`timescale 1ns/1ps

// ================================================================
// Testbench : tb_seg_driver
// 用 SCAN_CLKS=4, digits=0..7, 验证:
//   - 位选依次点亮 digit0..digit7(低有效)
//   - 段码与 7 段译码一致(含 dp=0)
//   - 一轮扫描后循环
// 结局: PASS / FAIL
// ================================================================

module tb_seg_driver;
    localparam SCAN_CLKS = 4;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg [31:0] digits = 32'h76543210;   // digit7=7 ... digit0=0
    reg  [7:0] dp = 8'h00;
    wire [7:0] seg_sel;
    wire [7:0] seg_data;

    seg_driver #(.SCAN_CLKS(SCAN_CLKS), .ACTIVE_LOW(1'b1)) u_dut (
        .clk(clk), .rst_n(rst_n), .digits(digits), .dp(dp),
        .seg_sel(seg_sel), .seg_data(seg_data)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    task check;
        input [31:0] val;
        input [31:0] exp;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (val !== exp) begin
                $display("ERROR: %s got=%0h exp=%0h", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    // 7 段高电平码(与 RTL 相同), 供 TB 独立核对
    function [6:0] seg7;
        input [3:0] n;
        begin
            case (n)
                4'h0: seg7 = 7'h3F; 4'h1: seg7 = 7'h06;
                4'h2: seg7 = 7'h5B; 4'h3: seg7 = 7'h4F;
                4'h4: seg7 = 7'h66; 4'h5: seg7 = 7'h6D;
                4'h6: seg7 = 7'h7D; 4'h7: seg7 = 7'h07;
                default: seg7 = 7'h00;
            endcase
        end
    endfunction

    localparam [7:0] EXP_SEL[0:7] = '{8'hFE, 8'hFD, 8'hFB, 8'hF7,
                                     8'hEF, 8'hDF, 8'hBF, 8'h7F};

    integer d;   // 当前 digit 下标
    initial begin
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;

        // 依次采样 8 个位选槽
        for (d = 0; d < 8; d = d + 1) begin
            wait (u_dut.digit_idx == d[2:0]);
            @(posedge clk);   // 稳定一拍
            #1;               // 组合输出已稳定
            check(seg_sel, EXP_SEL[d], "seg_sel");
            check(seg_data, {1'b1, ~seg7(d[3:0])}, "seg_data");
        end

        // 一轮结束应回绕到 digit0
        wait (u_dut.digit_idx == 3'd0);
        @(posedge clk);
        #1;
        check(seg_sel, EXP_SEL[0], "wrap to digit0");

        if (errors == 0)
            $display("PASS: seg_driver ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
