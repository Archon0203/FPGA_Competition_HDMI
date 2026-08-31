`timescale 1ns/1ps

// ================================================================
// Testbench : tb_fat32_file_reader
// 目标：对 FAT32 file reader 做 adversarial/self-checking 验证。
//
// 特点：
//   * FAT chain 由固定表项构造，不假设 cluster 连续。
//   * 数据 payload 有独立 golden byte sequence。
//   * block model 在 sector 内随机插入 din_valid stall。
//   * sector_ready 在一次 block transaction 服务期间保持为 1，
//     事务结束后至少拉低一拍，模拟 request/release 边界。
//   * 特别覆盖 FAT entry offset=508，防止 9-bit offset 被误写成 8-bit。
// ================================================================

module tb_fat32_file_reader;
    localparam integer SECTOR_BYTES = 512;
    localparam integer FAT_LBA      = 64;
    localparam integer DATA_LBA     = 256;
    localparam integer MAX_SECT     = 1024;
    localparam integer MAX_GOT      = 8192;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [31:0] start_cluster = 32'd0;
    reg [31:0] file_size = 32'd0;
    reg [31:0] fat_lba_base = FAT_LBA;
    reg [31:0] data_lba_base = DATA_LBA;
    reg [7:0] sectors_per_cluster = 8'd1;

    wire sector_req;
    wire [31:0] sector_lba;
    reg sector_ready = 1'b0;
    reg din_valid = 1'b0;
    reg [7:0] din = 8'd0;
    wire byte_valid;
    wire [7:0] byte_data;
    wire done;
    wire ok;

    fat32_file_reader #(
        .SECTOR_BYTES(SECTOR_BYTES),
        .STALL_TIMEOUT_CYCLES(50000)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .start_cluster(start_cluster),
        .file_size(file_size),
        .fat_lba_base(fat_lba_base),
        .data_lba_base(data_lba_base),
        .sectors_per_cluster(sectors_per_cluster),
        .sector_req(sector_req),
        .sector_lba(sector_lba),
        .sector_ready(sector_ready),
        .din_valid(din_valid),
        .din(din),
        .byte_valid(byte_valid),
        .byte_data(byte_data),
        .done(done),
        .ok(ok)
    );

    always #5 clk = ~clk;

    reg [7:0] mem [0:MAX_SECT-1][0:SECTOR_BYTES-1];
    reg [7:0] golden [0:MAX_GOT-1];
    reg [7:0] got    [0:MAX_GOT-1];

    integer golden_len;
    integer got_len;
    integer errors;
    integer checks;

    task mem_clear;
        integer s, b;
        begin
            for (s = 0; s < MAX_SECT; s = s + 1)
                for (b = 0; b < SECTOR_BYTES; b = b + 1)
                    mem[s][b] = 8'h00;
        end
    endtask

    task buffers_clear;
        integer i;
        begin
            golden_len = 0;
            got_len = 0;
            for (i = 0; i < MAX_GOT; i = i + 1) begin
                golden[i] = 8'h00;
                got[i] = 8'h00;
            end
        end
    endtask

    task set_fat_entry;
        input integer cluster;
        input [31:0] value;
        integer lba;
        integer off;
        begin
            lba = FAT_LBA + (cluster * 4) / SECTOR_BYTES;
            off = (cluster * 4) % SECTOR_BYTES;
            mem[lba][off+0] = value[7:0];
            mem[lba][off+1] = value[15:8];
            mem[lba][off+2] = value[23:16];
            mem[lba][off+3] = value[31:24];
        end
    endtask

    task put_cluster_bytes;
        input integer cluster;
        input integer start_index;
        input integer count;
        input integer seed;
        integer i;
        integer byte_in_cluster;
        integer sec_in_cluster;
        integer off;
        integer lba;
        reg [7:0] v;
        begin
            for (i = 0; i < count; i = i + 1) begin
                byte_in_cluster = i;
                sec_in_cluster = byte_in_cluster / SECTOR_BYTES;
                off = byte_in_cluster % SECTOR_BYTES;
                lba = DATA_LBA + (cluster - 2) * sectors_per_cluster + sec_in_cluster;
                v = (seed + start_index + i) & 8'hFF;
                mem[lba][off] = v;
                golden[start_index+i] = v;
            end
            if (start_index + count > golden_len)
                golden_len = start_index + count;
        end
    endtask

    task expect_equal;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] label_text;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("ERROR: %s actual=%0d expected=%0d", label_text, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_start;
        input [31:0] sc;
        input [31:0] fs;
        input [7:0] spc;
        begin
            start_cluster = sc;
            file_size = fs;
            sectors_per_cluster = spc;
            got_len = 0;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task wait_for_done;
        input integer max_cycles;
        integer c;
        begin
            c = 0;
            while (!done && c < max_cycles) begin
                @(posedge clk);
                c = c + 1;
            end
            if (!done) begin
                $display("ERROR: timeout waiting done after %0d cycles", max_cycles);
                errors = errors + 1;
            end
        end
    endtask

    task compare_payload;
        input integer expected_len;
        integer i;
        integer mismatches;
        begin
            expect_equal(got_len, expected_len, "payload length");
            mismatches = 0;
            for (i = 0; i < expected_len; i = i + 1) begin
                if (got[i] !== golden[i]) begin
                    if (mismatches < 8)
                        $display("ERROR: payload[%0d] got=%02x expected=%02x", i, got[i], golden[i]);
                    mismatches = mismatches + 1;
                end
            end
            if (mismatches != 0) begin
                $display("ERROR: payload mismatches=%0d", mismatches);
                errors = errors + mismatches;
            end
        end
    endtask

    // ---------------- randomized block-device model ----------------
    reg block_busy;
    reg [31:0] active_lba;
    reg [8:0] rd_index;
    reg [3:0] startup_delay;
    reg release_cycle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_busy <= 1'b0;
            active_lba <= 32'd0;
            rd_index <= 9'd0;
            startup_delay <= 4'd0;
            release_cycle <= 1'b0;
            sector_ready <= 1'b0;
            din_valid <= 1'b0;
            din <= 8'hFF;
        end else begin
            din_valid <= 1'b0;

            if (release_cycle) begin
                // Mandatory low-ready gap between two requests.
                sector_ready <= 1'b0;
                release_cycle <= 1'b0;
            end else if (!block_busy) begin
                sector_ready <= 1'b0;
                if (sector_req) begin
                    block_busy <= 1'b1;
                    active_lba <= sector_lba;
                    rd_index <= 9'd0;
                    startup_delay <= ($random & 4'h7);
                    sector_ready <= 1'b1;
                end
            end else begin
                sector_ready <= 1'b1;
                if (startup_delay != 0) begin
                    startup_delay <= startup_delay - 1'b1;
                end else if (($random & 32'h3) != 0) begin
                    // About 75% of cycles deliver one byte; the rest are stalls.
                    din_valid <= 1'b1;
                    if (active_lba < MAX_SECT)
                        din <= mem[active_lba][rd_index];
                    else
                        din <= 8'hEE;

                    if (rd_index == SECTOR_BYTES-1) begin
                        // Keep ready high for this registered final byte.
                        // On the next clock DUT observes ready=1/din_valid=1,
                        // then release_cycle drops ready for the mandatory gap.
                        block_busy <= 1'b0;
                        rd_index <= 9'd0;
                        sector_ready <= 1'b1;
                        release_cycle <= 1'b1;
                    end else begin
                        rd_index <= rd_index + 1'b1;
                    end
                end
            end
        end
    end

    always @(negedge clk) begin
        if (byte_valid) begin
            if (got_len < MAX_GOT) begin
                got[got_len] = byte_data;
                got_len = got_len + 1;
            end else begin
                $display("ERROR: got buffer overflow");
                errors = errors + 1;
            end
        end
    end

    initial begin
        errors = 0;
        checks = 0;
        mem_clear;
        buffers_clear;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // ------------------------------------------------------------
        // Case 0: zero-length file. No sector should be needed.
        // ------------------------------------------------------------
        $display("CASE0 zero-length");
        mem_clear; buffers_clear;
        pulse_start(32'd3, 32'd0, 8'd1);
        wait_for_done(100);
        expect_equal(ok, 1, "case0 ok");
        compare_payload(0);

        // ------------------------------------------------------------
        // Case 1: one cluster, 100 bytes (< sector).
        // ------------------------------------------------------------
        $display("CASE1 single cluster 100B");
        mem_clear; buffers_clear;
        sectors_per_cluster = 8'd1;
        set_fat_entry(3, 32'h0FFFFFFF);
        put_cluster_bytes(3, 0, 100, 16'h10);
        pulse_start(32'd3, 32'd100, 8'd1);
        wait_for_done(30000);
        expect_equal(ok, 1, "case1 ok");
        compare_payload(100);

        // ------------------------------------------------------------
        // Case 2: exact sector, no FAT traversal should be required.
        // ------------------------------------------------------------
        $display("CASE2 exact 512B");
        mem_clear; buffers_clear;
        sectors_per_cluster = 8'd1;
        set_fat_entry(3, 32'h0FFFFFFF);
        put_cluster_bytes(3, 0, 512, 16'h20);
        pulse_start(32'd3, 32'd512, 8'd1);
        wait_for_done(30000);
        expect_equal(ok, 1, "case2 ok");
        compare_payload(512);

        // ------------------------------------------------------------
        // Case 3: 513B, contiguous chain 3 -> 4.
        // ------------------------------------------------------------
        $display("CASE3 contiguous 513B");
        mem_clear; buffers_clear;
        sectors_per_cluster = 8'd1;
        set_fat_entry(3, 32'd4);
        set_fat_entry(4, 32'h0FFFFFFF);
        put_cluster_bytes(3, 0,   512, 16'h30);
        put_cluster_bytes(4, 512, 1,   16'h30);
        pulse_start(32'd3, 32'd513, 8'd1);
        wait_for_done(60000);
        expect_equal(ok, 1, "case3 ok");
        compare_payload(513);

        // ------------------------------------------------------------
        // Case 4: fragmented, SPC=2: 3 -> 7 -> 5, 2050B.
        // Exercises two sectors per cluster and non-contiguous FAT chain.
        // ------------------------------------------------------------
        $display("CASE4 fragmented SPC=2 2050B");
        mem_clear; buffers_clear;
        sectors_per_cluster = 8'd2;
        set_fat_entry(3, 32'd7);
        set_fat_entry(7, 32'd5);
        set_fat_entry(5, 32'h0FFFFFFF);
        put_cluster_bytes(3, 0,    1024, 16'h40);
        put_cluster_bytes(7, 1024, 1024, 16'h40);
        put_cluster_bytes(5, 2048, 2,    16'h40);
        pulse_start(32'd3, 32'd2050, 8'd2);
        wait_for_done(120000);
        expect_equal(ok, 1, "case4 ok");
        compare_payload(2050);

        // ------------------------------------------------------------
        // Case 5: premature EOC. Need 513B, but cluster 3 terminates.
        // Exactly 512 bytes may be emitted before failure.
        // ------------------------------------------------------------
        $display("CASE5 premature EOC");
        mem_clear; buffers_clear;
        sectors_per_cluster = 8'd1;
        set_fat_entry(3, 32'h0FFFFFFF);
        put_cluster_bytes(3, 0, 512, 16'h50);
        pulse_start(32'd3, 32'd513, 8'd1);
        wait_for_done(60000);
        expect_equal(ok, 0, "case5 must fail");
        compare_payload(512);

        // ------------------------------------------------------------
        // Case 6: invalid next cluster (free cluster 0).
        // ------------------------------------------------------------
        $display("CASE6 invalid/free next cluster");
        mem_clear; buffers_clear;
        sectors_per_cluster = 8'd1;
        set_fat_entry(3, 32'd0);
        put_cluster_bytes(3, 0, 512, 16'h60);
        pulse_start(32'd3, 32'd513, 8'd1);
        wait_for_done(60000);
        expect_equal(ok, 0, "case6 must fail");
        compare_payload(512);

        // ------------------------------------------------------------
        // Case 7: FAT offset 508 boundary. cluster 127 -> 130.
        // This specifically detects an erroneous 8-bit FAT offset register.
        // ------------------------------------------------------------
        $display("CASE7 FAT offset=508 boundary");
        mem_clear; buffers_clear;
        sectors_per_cluster = 8'd1;
        set_fat_entry(127, 32'd130);
        set_fat_entry(130, 32'h0FFFFFFF);
        put_cluster_bytes(127, 0,   512, 16'h70);
        put_cluster_bytes(130, 512, 1,   16'h70);
        pulse_start(32'd127, 32'd513, 8'd1);
        wait_for_done(70000);
        expect_equal(ok, 1, "case7 ok");
        compare_payload(513);

        // ------------------------------------------------------------
        // Case 8: illegal sectors_per_cluster=0 must fail immediately.
        // ------------------------------------------------------------
        $display("CASE8 invalid SPC=0");
        mem_clear; buffers_clear;
        pulse_start(32'd3, 32'd100, 8'd0);
        wait_for_done(100);
        expect_equal(ok, 0, "case8 must fail");
        compare_payload(0);

        if (errors == 0)
            $display("PASS: fat32_file_reader all adversarial cases passed (checks=%0d)", checks);
        else
            $display("FAIL: fat32_file_reader errors=%0d checks=%0d", errors, checks);

        $finish;
    end

endmodule
