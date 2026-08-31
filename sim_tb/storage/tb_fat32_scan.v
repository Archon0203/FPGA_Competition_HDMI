`timescale 1ns/1ps

// ================================================================
// Testbench : tb_fat32_scan
// 构造 FAT32 镜像:
//   LBA0  MBR: 分区类型 0x0C, 起始 LBA=2048
//   LBA2048 引导: bps=512 spc=1 reserved=1 fats=2 fat_sz=1 root_clu=2
//   LBA2051 根目录: TEST.BMP(cluster=3, size=100), 结束 0x00
// 验证: partition/BPB 解析, 根目录项, 文件索引写出, scan_ok/done。
// 结局: PASS / FAIL
// ================================================================

module tb_fat32_scan;
    localparam SECT = 512;
    localparam LBA_BOOT = 2048;
    localparam LBA_ROOT = 2051;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        start = 1'b0;
    wire       din_valid;
    wire [7:0] din;
    wire       sector_req;
    wire [31:0] sector_lba;
    wire       sector_ready;
    wire       scan_done, scan_ok, file_wr;
    wire [4:0]  file_count, file_index;
    wire [1:0]  file_type;
    wire [31:0] file_cluster, file_size;

    fat32_scan #(.FILE_MAX(8)) u_dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_ready(sector_ready),
        .din_valid(din_valid), .din(din),
        .scan_done(scan_done), .scan_ok(scan_ok),
        .file_count(file_count), .file_index(file_index),
        .file_type(file_type), .file_cluster(file_cluster),
        .file_size(file_size), .file_wr(file_wr)
    );

    always #5 clk = ~clk;

    // ---- 行为级扇区源 ----
    reg [7:0] sectbuf [0:2][0:SECT-1];
    reg [1:0] cursel = 2'd0;
    reg [8:0]  sidx = 9'd0;
    reg        req_prev = 1'b0;
    reg [31:0] last_lba = 32'd0;
    reg        rdy = 1'b0;

    assign din_valid    = rdy && (sidx < SECT);
    assign din          = (rdy && (sidx < SECT)) ? sectbuf[cursel][sidx] : 8'd0;
    assign sector_ready = rdy;

    function integer lba2sel;
        input [31:0] l;
        begin
            if (l == 0)                lba2sel = 0;
            else if (l == LBA_BOOT)    lba2sel = 1;
            else                       lba2sel = 2;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sidx <= 9'd0; rdy <= 1'b0; req_prev <= 1'b0; last_lba <= 32'd0;
        end else begin
            req_prev <= sector_req;
            if (sector_req && (!req_prev || sector_lba != last_lba)) begin
                last_lba  <= sector_lba;
                sidx     <= 9'd0;
                cursel   <= lba2sel(sector_lba);
                rdy      <= 1'b1;
            end else if (sector_req && rdy && sidx < SECT) begin
                sidx      <= sidx + 1'b1;
            end else begin
                rdy <= 1'b0;
            end
        end
    end

    integer errors = 0;
    integer checks = 0;
    integer i, j;

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

    task build_disk;
        begin
            for (i = 0; i < 3; i = i + 1)
                for (j = 0; j < SECT; j = j + 1) sectbuf[i][j] = 8'd0;

            // MBR: 分区表第一项在偏移 446; 类型 0x0C 在 450; start LBA 454
            sectbuf[0][446] = 8'h80;
            sectbuf[0][450] = 8'h0C;
            sectbuf[0][454] = 8'h00; sectbuf[0][455] = 8'h08;
            sectbuf[0][456] = 8'h00; sectbuf[0][457] = 8'h00;

            // 引导扇区 BPB
            sectbuf[1][11] = 8'h00; sectbuf[1][12] = 8'h02; // bps=512
            sectbuf[1][13] = 8'h01;                          // spc=1
            sectbuf[1][14] = 8'h01; sectbuf[1][15] = 8'h00;  // reserved=1
            sectbuf[1][16] = 8'h02;                          // fats=2
            sectbuf[1][36] = 8'h01; sectbuf[1][37] = 8'h00;
            sectbuf[1][38] = 8'h00; sectbuf[1][39] = 8'h00;  // fat_sz=1
            sectbuf[1][44] = 8'h02; sectbuf[1][45] = 8'h00;
            sectbuf[1][46] = 8'h00; sectbuf[1][47] = 8'h00;  // root_clu=2

            // 根目录: "TEST    BMP" cluster=3 size=100
            sectbuf[2][0] = 8'h54; sectbuf[2][1] = 8'h45;  // T E
            sectbuf[2][2] = 8'h53; sectbuf[2][3] = 8'h54;  // S T
            sectbuf[2][4] = 8'h20; sectbuf[2][5] = 8'h20;
            sectbuf[2][6] = 8'h20; sectbuf[2][7] = 8'h20;
            sectbuf[2][8] = 8'h42; sectbuf[2][9] = 8'h4D;  // B M
            sectbuf[2][10]= 8'h50;                          // P
            sectbuf[2][11]= 8'h20;                          // attr archive
            sectbuf[2][20]= 8'h00; sectbuf[2][21] = 8'h00;  // clu high 0
            sectbuf[2][26]= 8'h03; sectbuf[2][27] = 8'h00;  // clu low 3
            sectbuf[2][28]= 8'h64; sectbuf[2][29] = 8'h00;  // size 100
            sectbuf[2][30]= 8'h00; sectbuf[2][31] = 8'h00;
            sectbuf[2][32]= 8'h00;                          // 目录结束
        end
    endtask

    initial begin
        build_disk;
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        i = 0;
        while (!scan_done && i < 4000) begin
            @(posedge clk);
            i = i + 1;
        end
        #1;
        check(scan_done, 1, "scan done");
        check(scan_ok, 1, "scan ok");
        check(file_count, 1, "one file");
        check(file_type, 1, "type BMP");
        check(file_cluster, 3, "cluster 3");
        check(file_size, 100, "size 100");

        // 复用性：不复位，再次扫描同一镜像，文件计数应从 0 重新建立。
        sidx = 9'd0;
        rdy = 1'b0;
        req_prev = 1'b0;
        last_lba = 32'd0;
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        @(negedge clk);

        i = 0;
        while (!scan_done && i < 4000) begin
            @(posedge clk);
            i = i + 1;
        end
        #1;
        check(scan_done, 1, "second scan done");
        check(scan_ok, 1, "second scan ok");
        check(file_count, 1, "second one file");
        check(file_type, 1, "second type BMP");
        check(file_cluster, 3, "second cluster 3");
        check(file_size, 100, "second size 100");

        if (errors == 0)
            $display("PASS: fat32_scan ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
