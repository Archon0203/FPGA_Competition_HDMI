`timescale 1ns/1ps

// ================================================================
// Testbench : tb_bmp_parser
// 构造 640x480 24bit BMP 头(54 字节), 逐字节喂入, 核对
//   width=640 height=480 bpp=24 data_offset=54 bmp_ok=1, done 在首个像素字节置起。
// 另测非 "BM" 魔数 -> bmp_ok=0。
// 结局: PASS / FAIL
// ================================================================

module tb_bmp_parser;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [7:0] din = 8'd0;
    reg        din_valid = 1'b0;
    wire       done, bmp_ok;
    wire [15:0] width, height;
    wire [5:0]  bpp;
    wire [23:0] data_offset;

    bmp_parser u_dut (
        .clk(clk), .rst_n(rst_n), .din(din), .din_valid(din_valid),
        .done(done), .bmp_ok(bmp_ok), .width(width), .height(height),
        .bpp(bpp), .data_offset(data_offset)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer k;
    reg [7:0] hdr [0:53];   // 54 字节头

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

    // 构造标准 640x480 24bit 头
    task build_hdr;
        begin
            hdr[0]=8'h42; hdr[1]=8'h4D;             // 'BM'
            hdr[2]=8'h36; hdr[3]=8'h00; hdr[4]=8'h00; hdr[5]=8'h00; // file size 54(占位)
            hdr[6]=8'h00; hdr[7]=8'h00; hdr[8]=8'h00; hdr[9]=8'h00;
            hdr[10]=8'h36; hdr[11]=8'h00; hdr[12]=8'h00; hdr[13]=8'h00; // data_offset=54
            hdr[14]=8'h28; hdr[15]=8'h00; hdr[16]=8'h00; hdr[17]=8'h00; // info size 40
            hdr[18]=8'h80; hdr[19]=8'h02; hdr[20]=8'h00; hdr[21]=8'h00; // width 640
            hdr[22]=8'hE0; hdr[23]=8'h01; hdr[24]=8'h00; hdr[25]=8'h00; // height 480
            hdr[26]=8'h01; hdr[27]=8'h00;             // planes 1
            hdr[28]=8'h18; hdr[29]=8'h00;             // bpp 24
            hdr[30]=8'h00; hdr[31]=8'h00; hdr[32]=8'h00; hdr[33]=8'h00;
            hdr[34]=8'h00; hdr[35]=8'h00; hdr[36]=8'h00; hdr[37]=8'h00;
            hdr[38]=8'h00; hdr[39]=8'h00; hdr[40]=8'h00; hdr[41]=8'h00;
            hdr[42]=8'h00; hdr[43]=8'h00; hdr[44]=8'h00; hdr[45]=8'h00;
            hdr[46]=8'h00; hdr[47]=8'h00; hdr[48]=8'h00; hdr[49]=8'h00;
            hdr[50]=8'h00; hdr[51]=8'h00; hdr[52]=8'h00; hdr[53]=8'h00;
        end
    endtask

    // 喂 head_len 个字节
    task feed_n;
        input integer n;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                din = hdr[k]; din_valid = 1'b1;
            end
            @(posedge clk);
            din_valid = 1'b0;
        end
    endtask

    initial begin
        build_hdr;
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 喂 54 字节头
        feed_n(54);
        check(width, 640, "width"); check(height, 480, "height");
        check(bpp, 24, "bpp"); check(data_offset, 54, "data_offset");
        check(bmp_ok, 1, "bmp_ok"); check(done, 0, "done not yet before pixel");

        // 喂一个像素字节 -> done 置起
        @(posedge clk); din = 8'hAA; din_valid = 1'b1;
        @(posedge clk); #1;
        check(done, 1, "done on pixel start");
        din_valid = 1'b0;

        // 非 "BM" 魔数
        begin
            rst_n = 1'b0; #10; rst_n = 1'b1; #10;
            // 手工喂 2 字节 'X' 'Y'
            @(posedge clk); din = 8'h58; din_valid = 1'b1; @(posedge clk); din_valid = 1'b0;
            @(posedge clk); din = 8'h59; din_valid = 1'b1; @(posedge clk); din_valid = 1'b0;
            check(bmp_ok, 0, "bad magic bmp_ok");
        end

        if (errors == 0)
            $display("PASS: bmp_parser ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
