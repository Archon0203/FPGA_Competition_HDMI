`timescale 1ns/1ps

// P1-05B write-side provider-realistic integration regression:
// fragmented FAT32 BMP -> p1_media_framebuffer_loader -> arbiter ->
// cached adapter -> APUG011 application-port model.
module tb_p1_media_framebuffer_loader;
    localparam integer W = 17;
    localparam integer H = 12;
    localparam integer SECTOR_BYTES = 512;
    localparam integer FAT_LBA = 1;
    localparam integer DATA_LBA = 8;
    localparam integer MAX_SECT = 32;
    localparam integer MAX_FILE = 2048;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #3.333 clk = ~clk; // P1 SDRAM/write-domain target cadence

    reg start = 1'b0;
    reg [20:0] frame_base = 21'd0;
    reg [31:0] start_cluster = 32'd3;
    reg [31:0] file_size = 32'd0;
    reg [7:0] sectors_per_cluster = 8'd1;
    wire ready;

    wire sector_req;
    wire [31:0] sector_lba;
    reg sector_ready = 1'b0;
    reg sector_din_valid = 1'b0;
    reg [7:0] sector_din = 8'd0;

    wire writer_valid;
    wire [20:0] writer_addr;
    wire [31:0] writer_data;
    wire writer_ready;
    wire loader_busy, loader_done, loader_ok;
    wire loader_protocol_error, loader_source_error, loader_overflow;
    wire [15:0] bmp_width, bmp_height;
    wire [23:0] bmp_data_offset;
    wire file_done, file_ok, pixels_done, pixels_ok;

    wire mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire mem_wr_ready;
    wire arb_protocol_error;

    wire App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din;
    wire [3:0] App_wr_dm;
    wire App_rd_en;
    wire [20:0] App_rd_addr;
    wire Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire Sdr_init_done;
    wire Sdr_init_ref_vld;
    wire Sdr_busy;
    wire App_ref_req;
    wire adapter_ready;
    wire adapter_protocol_error;
    wire adapter_provider_fault;
    wire provider_protocol_error;
    wire [31:0] provider_app_write_count;

    reg [7:0] disk [0:MAX_SECT-1][0:SECTOR_BYTES-1];
    reg [7:0] file_mem [0:MAX_FILE-1];
    integer file_len;
    integer errors = 0;
    integer checks = 0;

    p1_media_framebuffer_loader #(
        .EXPECTED_WIDTH(W), .EXPECTED_HEIGHT(H), .FRAME_STRIDE_WORDS(W),
        .PIXEL_FIFO_DEPTH(32), .STALL_TIMEOUT_CYCLES(5000)
    ) loader (
        .clk(clk), .rst_n(rst_n), .start(start), .frame_base(frame_base), .ready(ready),
        .start_cluster(start_cluster), .file_size(file_size),
        .fat_lba_base(FAT_LBA), .data_lba_base(DATA_LBA),
        .sectors_per_cluster(sectors_per_cluster),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_ready(sector_ready), .sector_din_valid(sector_din_valid), .sector_din(sector_din),
        .mem_wr_valid(writer_valid), .mem_wr_addr(writer_addr), .mem_wr_data(writer_data), .mem_wr_ready(writer_ready),
        .busy(loader_busy), .done(loader_done), .ok(loader_ok),
        .protocol_error(loader_protocol_error), .source_error(loader_source_error), .overflow(loader_overflow),
        .bmp_width(bmp_width), .bmp_height(bmp_height), .bmp_data_offset(bmp_data_offset),
        .file_done(file_done), .file_ok(file_ok), .pixels_done(pixels_done), .pixels_ok(pixels_ok)
    );

    sdram_arbiter #(.MAX_READ_OUTSTANDING(8)) arbiter (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(writer_valid), .wr_addr(writer_addr), .wr_data(writer_data), .wr_ready(writer_ready),
        .rd_valid(1'b0), .rd_addr(21'd0), .rd_ready(), .rd_rvalid(), .rd_rdata(),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(), .mem_rd_addr(), .mem_rd_ready(1'b0), .mem_rvalid(1'b0), .mem_rdata(32'd0),
        .protocol_error(arb_protocol_error), .contention_seen(), .rd_outstanding_debug(),
        .read_accept_count_debug(), .write_accept_count_debug()
    );

    p1_sdram_cached_adapter adapter (
        .clk(clk), .rst_n(rst_n),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(1'b0), .mem_rd_addr(21'd0), .mem_rd_ready(), .mem_rvalid(), .mem_rdata(),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr), .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr), .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy), .App_ref_req(App_ref_req),
        .ready_for_traffic(adapter_ready), .protocol_error(adapter_protocol_error), .provider_fault(adapter_provider_fault),
        .contention_seen(), .read_outstanding_debug(), .read_accept_count_debug(), .write_accept_count_debug(),
        .app_read_word_count_debug(), .app_write_word_count_debug(),
        .read_cache_hit_count_debug(), .read_cache_miss_count_debug()
    );

    mock_apug011_app_port #(.MEM_WORDS(4096), .INIT_CYCLES(8), .READ_LATENCY(8)) provider (
        .clk(clk), .rst(!rst_n), .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr), .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr), .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
        .force_refresh(1'b0), .force_busy(1'b0), .inject_unsolicited_response(1'b0),
        .protocol_error(provider_protocol_error), .app_read_count(), .app_write_count(provider_app_write_count), .masked_word_count()
    );

    // Sector provider: keeps request/ready semantics identical to the P0
    // fixture while adding deterministic bubbles during byte streaming.
    reg block_busy = 1'b0;
    reg [31:0] active_lba = 32'd0;
    reg [8:0] rd_index = 9'd0;
    reg [1:0] bubble = 2'd0;
    reg release_cycle = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_busy <= 1'b0; active_lba <= 0; rd_index <= 0; bubble <= 0;
            release_cycle <= 1'b0; sector_ready <= 1'b0; sector_din_valid <= 1'b0; sector_din <= 8'hFF;
        end else begin
            sector_din_valid <= 1'b0;
            if (release_cycle) begin
                sector_ready <= 1'b0;
                release_cycle <= 1'b0;
            end else if (!block_busy) begin
                sector_ready <= 1'b0;
                if (sector_req) begin
                    block_busy <= 1'b1;
                    active_lba <= sector_lba;
                    rd_index <= 9'd0;
                    bubble <= 2'd2;
                    sector_ready <= 1'b1;
                end
            end else begin
                sector_ready <= 1'b1;
                if (bubble != 0)
                    bubble <= bubble - 1'b1;
                else begin
                    sector_din_valid <= 1'b1;
                    sector_din <= disk[active_lba][rd_index];
                    // Repeatable one-cycle stalls prove valid-only byte handling.
                    // A real SPI TF reader is far slower than this 150 MHz
                    // write-domain harness.  Keep one bubble after every byte
                    // (plus the initial two) so this is still a sustained
                    // valid-only source without inventing an impossible
                    // one-byte-per-SDR-clock producer.
                    bubble <= 2'd1;
                    if (rd_index == SECTOR_BYTES-1) begin
                        block_busy <= 1'b0;
                        rd_index <= 9'd0;
                        release_cycle <= 1'b1;
                    end else begin
                        rd_index <= rd_index + 1'b1;
                    end
                end
            end
        end
    end

    function [7:0] exp_r;
        input integer x; input integer y; begin exp_r = (8'h12 + x*5 + y*3); end
    endfunction
    function [7:0] exp_g;
        input integer x; input integer y; begin exp_g = (8'h30 + 8'h12*2 + x*3 + y*7); end
    endfunction
    function [7:0] exp_b;
        input integer x; input integer y; begin exp_b = (8'h80 + 8'h12 + x*11 + y); end
    endfunction
    function [23:0] expected_rgb;
        input integer x; input integer y; begin expected_rgb = {exp_r(x,y),exp_g(x,y),exp_b(x,y)}; end
    endfunction

    task check_int;
        input integer got; input integer exp; input [8*96-1:0] msg;
        begin checks=checks+1; if (got !== exp) begin $display("ERROR: %s got=%0d exp=%0d",msg,got,exp); errors=errors+1; end end
    endtask
    task check_word;
        input [31:0] got; input [31:0] exp; input [8*96-1:0] msg;
        begin checks=checks+1; if (got !== exp) begin $display("ERROR: %s got=%08x exp=%08x",msg,got,exp); errors=errors+1; end end
    endtask
    task clear_disk;
        integer s,b; begin for(s=0;s<MAX_SECT;s=s+1) for(b=0;b<SECTOR_BYTES;b=b+1) disk[s][b]=0; end
    endtask
    task set_fat;
        input integer cluster; input [31:0] value; integer off;
        begin off=cluster*4; disk[FAT_LBA][off]=value[7:0]; disk[FAT_LBA][off+1]=value[15:8]; disk[FAT_LBA][off+2]=value[23:16]; disk[FAT_LBA][off+3]=value[31:24]; end
    endtask
    task build_bmp;
        integer x,y,i,off,pad,rowbytes; reg [7:0] r,g,b;
        begin
            for(i=0;i<MAX_FILE;i=i+1) file_mem[i]=0;
            file_mem[0]="B"; file_mem[1]="M";
            rowbytes=W*3; pad=(4-(rowbytes%4))%4; file_len=54+(rowbytes+pad)*H;
            file_mem[2]=file_len[7:0]; file_mem[3]=file_len[15:8];
            file_mem[10]=8'd54; file_mem[14]=8'd40;
            file_mem[18]=W[7:0]; file_mem[19]=W[15:8];
            file_mem[22]=H[7:0]; file_mem[23]=H[15:8];
            file_mem[26]=8'd1; file_mem[28]=8'd24;
            off=54;
            for(y=H-1;y>=0;y=y-1) begin
                for(x=0;x<W;x=x+1) begin
                    r=exp_r(x,y); g=exp_g(x,y); b=exp_b(x,y);
                    file_mem[off]=b; file_mem[off+1]=g; file_mem[off+2]=r; off=off+3;
                end
                for(i=0;i<pad;i=i+1) begin file_mem[off]=8'hEE; off=off+1; end
            end
        end
    endtask
    task install_fragmented_file;
        integer i; integer lba;
        begin
            clear_disk;
            set_fat(3,32'd7); set_fat(7,32'h0FFFFFFF);
            for(i=0;i<file_len;i=i+1) begin
                if(i<512) lba=DATA_LBA+(3-2); else lba=DATA_LBA+(7-2);
                disk[lba][i%512]=file_mem[i];
            end
            file_size=file_len;
        end
    endtask
    task pulse_start;
        begin while(!ready) @(negedge clk); @(negedge clk); start=1'b1; @(negedge clk); start=1'b0; end
    endtask
    task wait_done;
        integer c; begin c=0; while(!loader_done && c<100000) begin @(negedge clk); c=c+1; end if(c>=100000) begin $display("ERROR: loader timeout"); errors=errors+1; end end
    endtask

    integer x,y,addr;
    integer writes_before_bad_file;
    initial begin
        clear_disk;
        repeat(5) @(posedge clk); rst_n=1'b1;
        wait(adapter_ready);
        build_bmp; install_fragmented_file; pulse_start; wait_done;
        // Adapter may still be completing its final internally registered
        // APUG011 group after the abstract writer has drained.
        repeat(32) @(posedge clk);
        check_int(loader_ok,1,"fragmented BMP loader success");
        check_int(loader_protocol_error,0,"loader protocol healthy");
        check_int(loader_source_error,0,"loader source healthy");
        check_int(loader_overflow,0,"loader no FIFO overflow");
        check_int(file_ok,1,"FAT reader success");
        check_int(pixels_ok,1,"BMP pixel stream success");
        check_int(bmp_width,W,"parsed width"); check_int(bmp_height,H,"parsed height"); check_int(bmp_data_offset,54,"parsed offset");
        check_int(arb_protocol_error,0,"arbiter protocol healthy");
        check_int(adapter_protocol_error,0,"cached adapter healthy");
        check_int(adapter_provider_fault,0,"adapter no provider fault");
        check_int(provider_protocol_error,0,"APUG provider protocol healthy");
        check_int(provider_app_write_count >= W*H,1,"provider accepted image writes");
        for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) begin
            addr=y*W+x;
            check_word(provider.mem[addr],{8'h00,expected_rgb(x,y)},"provider framebuffer RGB");
        end

        // CASE1: no-reset invalid BMP signature.  The loader must reject the
        // file before arming framebuffer_writer and must not overwrite the
        // successfully loaded image from CASE0.
        $display("CASE1 invalid BMP signature is rejected without writes");
        writes_before_bad_file = provider_app_write_count;
        file_mem[0] = 8'h00;
        install_fragmented_file;
        pulse_start;
        wait_done;
        repeat(16) @(posedge clk);
        check_int(loader_ok,0,"invalid BMP load fails");
        check_int(loader_source_error,1,"invalid BMP reports source error");
        check_int(loader_overflow,0,"invalid BMP has no overflow");
        check_int(provider_app_write_count,writes_before_bad_file,"invalid BMP caused no provider write");
        // Spot-check first, middle and final words survived the rejected load.
        check_word(provider.mem[0],{8'h00,expected_rgb(0,0)},"invalid BMP preserves first word");
        check_word(provider.mem[7*W+8],{8'h00,expected_rgb(8,7)},"invalid BMP preserves middle word");
        check_word(provider.mem[W*H-1],{8'h00,expected_rgb(W-1,H-1)},"invalid BMP preserves final word");
        if(errors==0) $display("PASS: p1_media_framebuffer_loader fragmented BMP -> cached APUG011 chain (checks=%0d, app_writes=%0d)",checks,provider_app_write_count);
        else $display("FAIL: p1_media_framebuffer_loader errors=%0d checks=%0d",errors,checks);
        $finish;
    end
    initial begin #3000000; $display("FAIL: p1_media_framebuffer_loader global timeout"); $finish; end
endmodule
