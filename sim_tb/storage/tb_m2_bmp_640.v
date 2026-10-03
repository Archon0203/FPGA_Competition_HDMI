`timescale 1ns/1ps
module tb_m2_bmp_640;
    reg clk=0, rst_n=0, cmd_valid=0;
    wire cmd_ready, sector_req, sector_consume_ready, catalog_valid, descriptor_valid;
    wire [31:0] sector_lba;
    wire [7:0] catalog_count, descriptor_image_id, error_code;
    wire [15:0] catalog_epoch, descriptor_width, descriptor_height;
    wire source_ready, source_busy, source_done, source_error;
    wire mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    reg streaming=0;
    reg [31:0] lba_q=0;
    reg [8:0] index_q=0;
    integer writes=0, errors=0, wait_count=0;
    integer paused_cycles=0;
    reg [11:0] stall_phase=0;
    wire mem_wr_ready = (stall_phase >= 12'd1600);
    integer expected_x=0, expected_y=479;
    reg [31:0] expected_data;
    reg [7:0] row_color;

    always #5 clk=~clk;
    function [7:0] disk_byte;
        input [31:0] lba;
        input [8:0] idx;
        integer cluster, byte_in_entry, next_cluster, off, pix, row, x, phase;
        begin
            disk_byte=0;
            if(lba==0) begin
                if(idx==450) disk_byte=8'h0c;
                if(idx==454) disk_byte=1;
            end else if(lba==1) begin
                case(idx)
                    11:disk_byte=0; 12:disk_byte=2;
                    13:disk_byte=1; 14:disk_byte=1;
                    16:disk_byte=1; 36:disk_byte=16;
                    44:disk_byte=2;
                    default:disk_byte=0;
                endcase
            end else if(lba>=2 && lba<18) begin
                off=(lba-2)*512+idx;
                cluster=off/4;
                byte_in_entry=off%4;
                next_cluster=(cluster==1803) ? 32'h0fffffff : cluster+1;
                if(cluster>=3 && cluster<=1803)
                    disk_byte=(next_cluster >> (8*byte_in_entry)) & 8'hff;
            end else if(lba==18) begin
                case(idx)
                    0:disk_byte=8'h49;
                    8:disk_byte=8'h42;
                    9:disk_byte=8'h4d;
                    10:disk_byte=8'h50;
                    11:disk_byte=8'h20;
                    26:disk_byte=3;
                    28:disk_byte=8'h36;
                    29:disk_byte=8'h10;
                    30:disk_byte=8'h0e;
                    default:disk_byte=0;
                endcase
            end else if(lba>=19 && lba<=1819) begin
                off=(lba-19)*512+idx;
                case(off)
                    0:disk_byte=8'h42; 1:disk_byte=8'h4d;
                    2:disk_byte=8'h36; 3:disk_byte=8'h10; 4:disk_byte=8'h0e;
                    10:disk_byte=54; 14:disk_byte=40;
                    18:disk_byte=8'h80; 19:disk_byte=8'h02;
                    22:disk_byte=8'he0; 23:disk_byte=8'h01;
                    26:disk_byte=1; 28:disk_byte=24;
                    default:begin
                        if(off>=54 && off<921654) begin
                            pix=off-54;
                            row=pix/1920;
                            x=(pix%1920)/3;
                            phase=pix%3;
                            case(phase)
                                0:disk_byte=x & 8'hff;
                                1:disk_byte=row & 8'hff;
                                default:disk_byte=8'h5a;
                            endcase
                        end
                    end
                endcase
            end
        end
    endfunction

    m2_real_media_service dut (
        .clk(clk),.rst_n(rst_n),.scan_start(1'b0),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_image_id(8'd0),
        .frame_base(21'd0),.sector_req(sector_req),.sector_lba(sector_lba),
        .sector_consume_ready(sector_consume_ready),
        .sector_ready(streaming),.sector_idle(!streaming),
        .sector_din_valid(streaming && sector_consume_ready),
        .sector_din(disk_byte(lba_q,index_q)),
        .sector_error(1'b0),.mem_wr_valid(mem_wr_valid),
        .mem_wr_addr(mem_wr_addr),.mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),.catalog_valid(catalog_valid),
        .catalog_count(catalog_count),.catalog_epoch(catalog_epoch),
        .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id),
        .descriptor_width(descriptor_width),.descriptor_height(descriptor_height),
        .source_ready(source_ready),.source_busy(source_busy),
        .source_done(source_done),.source_error(source_error),
        .error_code(error_code));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) stall_phase<=0;
        else begin
            stall_phase<=stall_phase+1'b1;
            if(streaming && !sector_consume_ready) paused_cycles<=paused_cycles+1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin streaming<=0; lba_q<=0; index_q<=0; end
        else if(!sector_req) begin streaming<=0; index_q<=0; end
        else if(!streaming) begin
            streaming<=1; lba_q<=sector_lba; index_q<=0;
        end else if(sector_consume_ready) begin
            if(index_q==511) streaming<=0;
            else index_q<=index_q+1'b1;
        end
    end

    always @(posedge clk) if(rst_n && mem_wr_valid && mem_wr_ready) begin
        row_color=479-expected_y;
        expected_data={8'h00,8'h5a,row_color,expected_x[7:0]};
        if(mem_wr_addr !== expected_y*640+expected_x ||
           mem_wr_data !== expected_data) begin
            if(errors<8) $display("ERROR: pixel %0d addr=%0d data=%h",writes,mem_wr_addr,mem_wr_data);
            errors=errors+1;
        end
        writes=writes+1;
        if(expected_x==639) begin expected_x=0; expected_y=expected_y-1; end
        else expected_x=expected_x+1;
    end

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        while(!cmd_ready && wait_count<5000) begin @(negedge clk); wait_count=wait_count+1; end
        if(!cmd_ready || catalog_count!=1) $fatal(1,"FAIL: 640 catalog");
        @(negedge clk); cmd_valid=1;
        @(negedge clk); cmd_valid=0;
        wait_count=0;
        while(!source_done && !source_error && wait_count<5000000) begin
            @(negedge clk); wait_count=wait_count+1;
        end
        if(!source_done || source_error || writes!=307200 || expected_y!=-1 ||
           paused_cycles==0 ||
           descriptor_width!=640 || descriptor_height!=480) begin
            $display("FAIL: 640 BMP done=%b err=%b writes=%0d y=%0d size=%0d x %0d code=%h",
                     source_done,source_error,writes,expected_y,
                     descriptor_width,descriptor_height,error_code);
            errors=errors+1;
        end
        if(errors==0) $display("PASS: m2_bmp_640 writes=%0d paused=%0d",writes,paused_cycles);
        else $fatal(1,"FAIL: m2_bmp_640 errors=%0d",errors);
        $finish;
    end
endmodule
