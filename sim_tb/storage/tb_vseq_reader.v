`timescale 1ns/1ps

// ================================================================
// Testbench : tb_vseq_reader
// 构造 .vseq: W=4 H=2 bpp=16 fps=30 frame_count=2 -> frame_size=16字节。
// 验证: 头字段、VSEQ 魔数、header_done、每帧帧起止、全部帧完成。
// 结局: PASS / FAIL
// ================================================================

module tb_vseq_reader;
    localparam FSZ = 16;   // frame_size = 4*2*16/8
    localparam NF  = 2;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        din_valid = 1'b0;
    reg  [7:0] din = 8'd0;
    wire       vseq_ok, header_done;
    wire [15:0] width, height, frame_count;
    wire [5:0]  bpp;
    wire [7:0]  fps;
    wire        byte_valid;
    wire [7:0]  byte_data;
    wire        frame_start, frame_done, all_done;

    vseq_reader u_dut (
        .clk(clk), .rst_n(rst_n), .din_valid(din_valid), .din(din),
        .vseq_ok(vseq_ok), .header_done(header_done),
        .width(width), .height(height), .bpp(bpp), .fps(fps), .frame_count(frame_count),
        .byte_valid(byte_valid), .byte_data(byte_data),
        .frame_start(frame_start), .frame_done(frame_done), .all_done(all_done)
    );

    // 第二个实例：用真实推荐分辨率 320x240x16，专门验证 frame_size 位宽不再被截断。
    wire [15:0] big_width, big_height, big_frame_count;
    wire [5:0]  big_bpp;
    wire [7:0]  big_fps;
    wire        big_vseq_ok, big_header_done;
    wire        big_byte_valid, big_frame_start, big_frame_done, big_all_done;
    wire [7:0]  big_byte_data;

    vseq_reader u_big (
        .clk(clk), .rst_n(rst_n), .din_valid(din_valid), .din(din),
        .vseq_ok(big_vseq_ok), .header_done(big_header_done),
        .width(big_width), .height(big_height), .bpp(big_bpp),
        .fps(big_fps), .frame_count(big_frame_count),
        .byte_valid(big_byte_valid), .byte_data(big_byte_data),
        .frame_start(big_frame_start), .frame_done(big_frame_done), .all_done(big_all_done)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    reg  [7:0] hdr [0:63];
    reg  [7:0] bighdr [0:63];
    integer b;
    integer f, j;

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

    // 构造头
    task build_hdr;
        begin
            for (b = 0; b < 64; b = b + 1) hdr[b] = 8'd0;
            hdr[0]=8'h56; hdr[1]=8'h53; hdr[2]=8'h45; hdr[3]=8'h51; // VSEQ
            hdr[4]=8'h01;                   // version
            hdr[5]=8'h04; hdr[6]=8'h00;     // width=4
            hdr[7]=8'h02; hdr[8]=8'h00;     // height=2
            hdr[9]=8'h10;                   // bpp=16
            hdr[10]=8'd30;                  // fps=30
            hdr[11]=8'h02; hdr[12]=8'h00;   // frame_count=2
        end
    endtask

    task build_big_hdr;
        begin
            for (b = 0; b < 64; b = b + 1) bighdr[b] = 8'd0;
            bighdr[0]=8'h56; bighdr[1]=8'h53; bighdr[2]=8'h45; bighdr[3]=8'h51; // VSEQ
            bighdr[4]=8'h01;                   // version
            bighdr[5]=8'h40; bighdr[6]=8'h01;  // width=320 (0x140)
            bighdr[7]=8'hF0; bighdr[8]=8'h00;  // height=240 (0xF0)
            bighdr[9]=8'h10;                   // bpp=16
            bighdr[10]=8'd30;                  // fps=30
            bighdr[11]=8'h01; bighdr[12]=8'h00; // frame_count=1
        end
    endtask

    // 喂字节(在 negedge 设置, 消费沿在 posedge; 返回前 din_valid 拉低)
    task feed;
        input [7:0] b;
        begin
            @(negedge clk);
            din = b; din_valid = 1'b1;
            @(posedge clk);
            din_valid = 1'b0;
        end
    endtask

    initial begin
        build_hdr;
        build_big_hdr;
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 头 64 字节
        for (b = 0; b < 64; b = b + 1) feed(hdr[b]);

        #1;
        check(vseq_ok, 1, "vseq_ok");
        check(header_done, 1, "header_done");
        check(width, 4, "width"); check(height, 2, "height");
        check(bpp, 16, "bpp"); check(fps, 30, "fps");
        check(frame_count, 2, "frame_count");

        // 两帧体: 每帧 16 字节
        for (f = 0; f < NF; f = f + 1) begin
            for (j = 0; j < FSZ; j = j + 1) begin
                @(negedge clk);
                din = f*FSZ + j;       // 可区分帧号(截断为 8bit)
                din_valid = 1'b1;
                #1;
                check(byte_valid, 1, "body byte valid");
                check(byte_data, f*FSZ + j, "body byte data");
                check(frame_start, (j == 0), "frame_start");
                check(frame_done, (j == FSZ-1), "frame_done");
                @(posedge clk);
                din_valid = 1'b0;
            end
        end
        #1;
        check(all_done, 1, "all frames done");

        // 真实 320x240x16 头：frame_size 应为 153600 字节，而不是 16bit 乘法截断后的错误值。
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;
        for (b = 0; b < 64; b = b + 1) feed(bighdr[b]);
        #1;
        check(big_vseq_ok, 1, "big vseq_ok");
        check(big_header_done, 1, "big header_done");
        check(big_width, 320, "big width");
        check(big_height, 240, "big height");
        check(big_bpp, 16, "big bpp");
        check(u_big.frame_size, 153600, "big frame_size");

        if (errors == 0)
            $display("PASS: vseq_reader ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
