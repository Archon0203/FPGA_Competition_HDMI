`timescale 1ns/1ps

// ================================================================
// 彩条源 : 8 竖条, 输出 BT.601 YCbCr(组合逻辑, 仅供集成 tb 使用)
// ================================================================
module color_bar_src (
    input  wire [11:0] px,
    input  wire        pix_valid,
    output reg  [7:0]  y,
    output reg  [7:0]  cb,
    output reg  [7:0]  cr
);
    reg [2:0] bar;
    always @(*) begin
        bar = px / 12'd80;
        if (!pix_valid) begin
            y = 8'd0; cb = 8'd0; cr = 8'd0;
        end else begin
            case (bar)
                3'd0: begin y=8'd235; cb=8'd128; cr=8'd128; end
                3'd1: begin y=8'd226; cb=8'd16;  cr=8'd146; end
                3'd2: begin y=8'd171; cb=8'd208; cr=8'd16;  end
                3'd3: begin y=8'd146; cb=8'd54;  cr=8'd166; end
                3'd4: begin y=8'd105; cb=8'd240; cr=8'd216; end
                3'd5: begin y=8'd81;  cb=8'd84;  cr=8'd240; end
                3'd6: begin y=8'd41;  cb=8'd240; cr=8'd116; end
                default: begin y=8'd16; cb=8'd128; cr=8'd128; end
            endcase
        end
    end
endmodule

// ================================================================
// Testbench : tb_mini_top
// 集成验证"mini-top 显示链"(含 YUV420 上采样与坐标延迟):
//   vga_timing -> YUV420彩条源 -> yuv420_upsample -> color_space(YUV->RGB)
//   -> image_enhance(透传) -> transition(直通) -> osd_overlay(实心块)
// 校验: 每帧有效像素/行同步数; OSD 区=前景色; 非 OSD 区=彩条经 color_space。
// 结局: PASS / FAIL
// ================================================================

module tb_mini_top;
    localparam H_ACTIVE = 640, V_ACTIVE = 480;
    localparam H_TOTAL  = 800, V_TOTAL  = 525;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    wire       hs, vs, de;
    wire [11:0] pixel_x, pixel_y;

    vga_timing #(.H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE)) u_vga (
        .clk_pix(clk), .rst_n(rst_n), .hs(hs), .vs(vs), .de(de),
        .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    wire [7:0] y_src, cb_src, cr_src;
    wire       c_valid = de && (pixel_x[0] == 1'b0) && (pixel_y[0] == 1'b0);
    color_bar_src u_src (.px(pixel_x), .pix_valid(de), .y(y_src), .cb(cb_src), .cr(cr_src));

    wire [7:0] y_up, cb_up, cr_up;
    wire [11:0] upx, upy;
    wire       v_up;
    yuv420_upsample #(.HW(H_ACTIVE/2), .DW(8)) u_yuv (
        .clk(clk), .rst_n(rst_n), .pix_valid(de), .px(pixel_x), .py(pixel_y),
        .c_valid(c_valid), .y_in(y_src), .cb_in(cb_src), .cr_in(cr_src),
        .y_out(y_up), .cb_out(cb_up), .cr_out(cr_up), .out_valid(v_up),
        .out_px(upx), .out_py(upy)
    );

    wire [7:0] r_cs, g_cs, b_cs;
    wire       v_cs;
    color_space u_cs (
        .y(y_up), .cb(cb_up), .cr(cr_up), .pixel_valid(v_up),
        .r(r_cs), .g(g_cs), .b(b_cs), .out_valid(v_cs)
    );

    wire [7:0] r_e, g_e, b_e;
    wire       v_e;
    image_enhance #(.DW(8)) u_en (
        .pixel_valid(v_cs), .r_in(r_cs), .g_in(g_cs), .b_in(b_cs),
        .gain(8'd64), .bias(8'sd0),
        .r_out(r_e), .g_out(g_e), .b_out(b_e), .out_valid(v_e)
    );

    wire [7:0] r_t, g_t, b_t;
    wire       v_t;
    transition #(.DST_W(H_ACTIVE), .DW(8)) u_tr (
        .clk(clk), .rst_n(rst_n), .valid(v_e), .mode(2'd0), .t(8'd0),
        .ax(upx), .ay(upy),
        .a_r(r_e), .a_g(g_e), .a_b(b_e),
        .b_r(r_e), .b_g(g_e), .b_b(b_e),
        .out_r(r_t), .out_g(g_t), .out_b(b_t), .out_valid(v_t)
    );

    wire [7:0] r_o, g_o, b_o;
    wire       v_o;
    osd_overlay #(.FW(8), .FH(16), .DW(8)) u_osd (
        .clk(clk), .rst_n(rst_n), .valid(v_t), .x(upx), .y(upy),
        .r_in(r_t), .g_in(g_t), .b_in(b_t),
        .osd_en(1'b1), .osd_x(12'd100), .osd_y(12'd100), .char_code(4'd1),
        .fg_r(8'd255), .fg_g(8'd0), .fg_b(8'd0),
        .out_r(r_o), .out_g(g_o), .out_b(b_o), .out_valid(v_o)
    );

    wire [7:0] y_ref, cb_ref, cr_ref;
    color_bar_src u_ref_src (.px(upx), .pix_valid(v_up), .y(y_ref), .cb(cb_ref), .cr(cr_ref));

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer frames = 0;
    integer active_px = 0;
    integer hs_count = 0;
    reg     prev_vs, prev_hs;

    // 参考 color_space(与 tb_color_space 相同)
    function [7:0] ref_r;
        input [7:0] iy, icb, icr;
        reg signed [31:0] off, s;
        begin
            off = (($signed({1'b0,iy}) - 32'sd16) * 32'sd298)
                + (($signed({2'b00,icr}) - 32'sd128) * 32'sd409)
                + 32'sd128;
            s   = off >>> 8;
            ref_r = (s < 0) ? 8'd0 : ((s > 255) ? 8'd255 : s[7:0]);
        end
    endfunction
    function [7:0] ref_g;
        input [7:0] iy, icb, icr;
        reg signed [31:0] off, s;
        begin
            off = (($signed({1'b0,iy}) - 32'sd16) * 32'sd298)
                + (($signed({2'b00,icb}) - 32'sd128) * -32'sd100)
                + (($signed({2'b00,icr}) - 32'sd128) * -32'sd208)
                + 32'sd128;
            s   = off >>> 8;
            ref_g = (s < 0) ? 8'd0 : ((s > 255) ? 8'd255 : s[7:0]);
        end
    endfunction
    function [7:0] ref_b;
        input [7:0] iy, icb, icr;
        reg signed [31:0] off, s;
        begin
            off = (($signed({1'b0,iy}) - 32'sd16) * 32'sd298)
                + (($signed({2'b00,icb}) - 32'sd128) * 32'sd516)
                + 32'sd128;
            s   = off >>> 8;
            ref_b = (s < 0) ? 8'd0 : ((s > 255) ? 8'd255 : s[7:0]);
        end
    endfunction

    task check;
        input [31:0] val;
        input [31:0] exp;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (val !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (de) begin
            active_px = active_px + 1;
        end
        if (v_o) begin
            // 逐像素核对: OSD 区(100..107,100..115) => 前景红; 其他 => 彩条参考色
            if (upx >= 100 && upx < 108 && upy >= 100 && upy < 116) begin
                checks = checks + 1;
                if (r_o !== 8'd255 || g_o !== 8'd0 || b_o !== 8'd0) begin
                    $display("ERROR: OSD pixel (%0d,%0d) r=%0d g=%0d b=%0d", upx, upy, r_o, g_o, b_o);
                    errors = errors + 1;
                end
            end else begin
                checks = checks + 1;
                if (r_o !== ref_r(y_ref, cb_ref, cr_ref) ||
                    g_o !== ref_g(y_ref, cb_ref, cr_ref) ||
                    b_o !== ref_b(y_ref, cb_ref, cr_ref)) begin
                    if (errors < 5)
                        $display("ERROR: color (%0d,%0d) r=%0d exp=%0d", upx, upy, r_o, ref_r(y_ref,cb_ref,cr_ref));
                    errors = errors + 1;
                end
            end
        end
        if (hs && !prev_hs) hs_count = hs_count + 1;
        prev_hs <= hs;
        if (vs && !prev_vs) begin
            if (frames > 0) begin
                checks = checks + 1;
                if (active_px != H_ACTIVE * V_ACTIVE) begin
                    $display("ERROR: frame active_px=%0d expect %0d", active_px, H_ACTIVE*V_ACTIVE);
                    errors = errors + 1;
                end
                checks = checks + 1;
                if (hs_count != V_TOTAL) begin
                    $display("ERROR: frame hs=%0d expect %0d", hs_count, V_TOTAL);
                    errors = errors + 1;
                end
            end
            frames = frames + 1;
            active_px = 0;
            hs_count = 0;
        end
        prev_vs <= vs;
    end

    initial begin
        rst_n = 1'b0;
        #20; rst_n = 1'b1;
        while (frames < 3) @(posedge clk);
        #20;
        if (errors == 0)
            $display("PASS: mini_top chain ok (frames=%0d checks=%0d)", frames, checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
