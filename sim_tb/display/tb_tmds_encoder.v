`timescale 1ns/1ps

// ================================================================
// Testbench : tb_tmds_encoder
// 使用独立的参考编码器逐拍比对 10bit 输出，并额外校验：
//   1) 消隐期四种控制码完全匹配；
//   2) 数据期 disparity 计数器始终有界；
//   3) 复位后输出为 0。
// 结局: PASS / FAIL
// ================================================================

module tb_tmds_encoder;
    localparam [9:0] CTRL_00 = 10'b1101010100;
    localparam [9:0] CTRL_01 = 10'b0010101011;
    localparam [9:0] CTRL_10 = 10'b0101010100;
    localparam [9:0] CTRL_11 = 10'b1010101011;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        de = 1'b0;
    reg        c0 = 1'b0;
    reg        c1 = 1'b0;
    reg  [7:0] din = 8'd0;
    wire [9:0] dout;

    tmds_encoder #(.DW(8)) u_dut (
        .clk(clk), .rst_n(rst_n), .de(de), .c0(c0), .c1(c1), .din(din), .dout(dout)
    );

    always #5 clk = ~clk;

    // 参考编码器状态
    reg             p_de, p_c0, p_c1;
    reg  [7:0]      p_din;
    reg  [9:0]      ref_q;
    reg signed [4:0] ref_cnt;

    integer errors = 0;
    integer checks = 0;
    integer k;

    function [3:0] cnt8;
        input [7:0] v;
        integer i;
        begin
            cnt8 = 4'd0;
            for (i = 0; i < 8; i = i + 1)
                cnt8 = cnt8 + v[i];
        end
    endfunction

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

    // 参考编码：由上一拍输入计算本拍 DUT 应输出的编码
    always @(posedge clk or negedge rst_n) begin : ref_proc
        reg [3:0] n1d, n1q, n0q;
        reg [8:0] qm;
        reg       d1, d2, d3;
        integer   i;
        reg signed [4:0] next_cnt;
        begin
            if (!rst_n) begin
                p_de <= 1'b0; p_c0 <= 1'b0; p_c1 <= 1'b0;
                p_din <= 8'd0;
                ref_q <= 10'd0;
                ref_cnt <= 5'sd0;
            end else begin
                if (!p_de) begin
                    case ({p_c1, p_c0})
                        2'b00:   ref_q <= CTRL_00;
                        2'b01:   ref_q <= CTRL_01;
                        2'b10:   ref_q <= CTRL_10;
                        default: ref_q <= CTRL_11;
                    endcase
                    ref_cnt <= 5'sd0;
                end else begin
                    n1d = cnt8(p_din);
                    d1  = (n1d > 4'd4) || ((n1d == 4'd4) && (p_din[0] == 1'b0));
                    qm[0] = p_din[0];
                    for (i = 1; i < 8; i = i + 1)
                        qm[i] = d1 ? (qm[i-1] ~^ p_din[i]) : (qm[i-1] ^ p_din[i]);
                    qm[8] = d1 ? 1'b0 : 1'b1;

                    n1q = cnt8(qm[7:0]);
                    n0q = 4'd8 - n1q;
                    d2  = (ref_cnt == 5'sd0) || (n1q == n0q);
                    d3  = ((ref_cnt > 5'sd0) && (n1q > n0q)) ||
                          ((ref_cnt < 5'sd0) && (n0q > n1q));

                    if (d2) begin
                        ref_q[9]   <= ~qm[8];
                        ref_q[8]   <= qm[8];
                        ref_q[7:0] <= qm[8] ? qm[7:0] : ~qm[7:0];
                        next_cnt = qm[8] ? (ref_cnt + $signed({2'b00,n1q}) - $signed({2'b00,n0q}))
                                         : (ref_cnt + $signed({2'b00,n0q}) - $signed({2'b00,n1q}));
                    end else if (d3) begin
                        ref_q[9]   <= 1'b1;
                        ref_q[8]   <= qm[8];
                        ref_q[7:0] <= ~qm[7:0];
                        next_cnt = ref_cnt + (qm[8] ? 6'sd2 : 6'sd0) + $signed({2'b00,n0q}) - $signed({2'b00,n1q});
                    end else begin
                        ref_q[9]   <= 1'b0;
                        ref_q[8]   <= qm[8];
                        ref_q[7:0] <= qm[7:0];
                        next_cnt = ref_cnt - (qm[8] ? 6'sd0 : 6'sd2) + $signed({2'b00,n1q}) - $signed({2'b00,n0q});
                    end
                    ref_cnt <= next_cnt;
                end

                p_de  <= de;
                p_c0  <= c0;
                p_c1  <= c1;
                p_din <= din;
            end
        end
    end

    initial begin
        rst_n = 1'b0; #20;
        check(dout, 10'd0, "reset dout");
        rst_n = 1'b1; #10;

        // 四种控制码
        begin : ctrl_cases
            integer cc;
            for (cc = 0; cc < 4; cc = cc + 1) begin
                @(negedge clk);
                de = 1'b0; c0 = cc[0]; c1 = cc[1];
                @(posedge clk); #1;
                @(negedge clk);
                @(posedge clk); #1;
                case (cc)
                    0: check(dout, CTRL_00, "ctrl 00");
                    1: check(dout, CTRL_01, "ctrl 01");
                    2: check(dout, CTRL_10, "ctrl 10");
                    3: check(dout, CTRL_11, "ctrl 11");
                endcase
            end
        end

        // 数据期：遍历边界和典型值，逐拍与参考编码器比对
        begin : data_cases
            reg [7:0] stimulus [0:31];
            integer di;
            stimulus[0] = 8'h00; stimulus[1] = 8'hFF; stimulus[2] = 8'h01; stimulus[3] = 8'hFE;
            stimulus[4] = 8'h80; stimulus[5] = 8'h7F; stimulus[6] = 8'h55; stimulus[7] = 8'hAA;
            for (di = 8; di < 32; di = di + 1)
                stimulus[di] = (di * 37 + 11);

            for (di = 0; di < 32; di = di + 1) begin
                @(negedge clk);
                de = 1'b1; c0 = 1'b0; c1 = 1'b0; din = stimulus[di];
                @(posedge clk); #1;
                check(dout, ref_q, "tmds data encode");
                if (u_dut.cnt > 10 || u_dut.cnt < -10) begin
                    $display("ERROR: disparity out of bound cnt=%0d", u_dut.cnt);
                    errors = errors + 1;
                end
            end
        end

        // 最后回到消隐控制码，验证 disparity 复位
        @(negedge clk);
        de = 1'b0; c0 = 1'b0; c1 = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        @(posedge clk); #1;
        check(dout, CTRL_10, "ctrl 10 after data");

        if (errors == 0)
            $display("PASS: tmds_encoder ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
