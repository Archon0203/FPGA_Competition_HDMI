`timescale 1ns/1ps
module tb_m2_slave_tf_media_core #(
    parameter integer SUPERFLOPPY = 0
);
    reg clk=0, rst_n=0, cmd_valid=0;
    wire cmd_ready, sd_ncs, sd_sclk, sd_mosi, mem_wr_valid;
    reg sd_miso=1;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire catalog_valid, descriptor_valid, source_ready, source_busy;
    wire source_done, source_error;
    wire [7:0] catalog_count, descriptor_image_id, error_code;
    wire [15:0] catalog_epoch, descriptor_width, descriptor_height;
    reg [7:0] disk [0:4][0:511];
    reg [7:0] responses [0:530];
    reg [7:0] command [0:5];
    reg [7:0] mosi_shift=0;
    reg [2:0] bit_count=0;
    integer head=0,tail=0,command_count=0,cmd0_count=0,cmd17_count=0;
    integer i,j,errors=0,writes=0,wait_count=0;
    reg [31:0] pixels [0:3];
    reg [31:0] master_pixels [0:3];
    reg write_fence=0, packet_start=0, frame_boundary=0;
    reg [15:0] packet_credit=0;
    reg read_response_valid=0;
    reg [31:0] read_response_data=0;
    wire read_valid, packet_valid, packet_last, packet_ready;
    wire [20:0] read_addr, master_write_addr, front_base;
    wire [31:0] packet_data, master_write_data;
    wire master_write_valid, front_valid, pending_swap, commit_pulse;
    wire [15:0] front_frame_id;
    wire [7:0] front_image_id;
    wire packet_source_done, packet_source_error;
    wire commit_error, protocol_error, link_ready;
    integer master_writes=0;
    integer held_sector_index=0;
    integer deselected_clock_edges=0;
    reg [7:0] received_byte;
    reg [31:0] command_lba;

    always #5 clk=~clk;
    always @(posedge clk) begin
        if (rst_n && dut.u_sector.official_clk_div !==
            (dut.u_sector.reader_init_done ? 16'd0 : 16'd30))
            $fatal(1, "SPI initialization/data divider mismatch");
    end
    m2_slave_tf_media_core #(.SPI_CLK_DIV(2),.SPI_INIT_CLK_DIV(32),
                             .SPI_MODE3(1),
                             .WIDTH(2),.HEIGHT(2)) dut (
        .clk(clk),.rst_n(rst_n),.scan_start(1'b0),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
        .cmd_image_id(8'd0),.frame_base(21'd0),
        .sd_ncs(sd_ncs),.sd_sclk(sd_sclk),
        .sd_mosi(sd_mosi),.sd_miso(sd_miso),
        .mem_wr_valid(mem_wr_valid),.mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data),.mem_wr_ready(1'b1),
        .catalog_valid(catalog_valid),.catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch),
        .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id),
        .descriptor_width(descriptor_width),
        .descriptor_height(descriptor_height),
        .source_ready(source_ready),.source_busy(source_busy),
        .source_done(source_done),.source_error(source_error),
        .error_code(error_code));

    m2_frame_packet_source #(.WIDTH(2),.HEIGHT(2)) u_packet_source (
        .clk(clk),.rst_n(rst_n),.start(packet_start),
        .frame_ready(write_fence),.frame_base(21'd0),
        .frame_id(16'd1),.image_id(8'd0),.credit_add(packet_credit),
        .source_ready(),.source_busy(),.source_done(packet_source_done),
        .source_error(packet_source_error),.credit_level(),
        .mem_rd_valid(read_valid),.mem_rd_addr(read_addr),
        .mem_rd_ready(1'b1),.mem_rvalid(read_response_valid),
        .mem_rdata(read_response_data),.packet_valid(packet_valid),
        .packet_data(packet_data),.packet_last(packet_last),
        .packet_ready(packet_ready));
    m2_master_line_core #(.WIDTH(2),.HEIGHT(2),.BASE_B(4)) u_master (
        .clk(clk),.rst_n(rst_n),.packet_valid(packet_valid),
        .packet_data(packet_data),.packet_last(packet_last),
        .packet_ready(packet_ready),.mem_wr_valid(master_write_valid),
        .mem_wr_addr(master_write_addr),.mem_wr_data(master_write_data),
        .mem_wr_ready(1'b1),.frame_boundary(frame_boundary),
        .front_base(front_base),.front_valid(front_valid),
        .front_frame_id(front_frame_id),.front_image_id(front_image_id),
        .pending_swap(pending_swap),.commit_pulse(commit_pulse),
        .commit_error(commit_error),.protocol_error(protocol_error),
        .link_ready(link_ready));

    // SPI card shifts MISO on falling SCLK and samples MOSI on rising SCLK.
    always @(posedge sd_sclk) begin
        if (rst_n && sd_ncs) begin
            if (sd_mosi !== 1'b1)
                $fatal(1, "deselected SPI clock without 0xff on MOSI");
            deselected_clock_edges=deselected_clock_edges+1;
        end
    end
    always @(negedge sd_sclk or posedge sd_ncs) begin
        if(sd_ncs) sd_miso<=1;
        else sd_miso <= (head<tail) ? responses[head][7-bit_count] : 1'b1;
    end
    always @(posedge sd_sclk or posedge sd_ncs) begin
        if(sd_ncs) begin
            bit_count=0; mosi_shift=0; command_count=0;
            head=0; tail=0;
        end else begin
            mosi_shift={mosi_shift[6:0],sd_mosi};
            if(bit_count==7) begin
                received_byte=mosi_shift;
                bit_count=0;
                if(head<tail) head=head+1;
                if(command_count==0) begin
                    if(received_byte[7:6]==2'b01) begin
                        command[0]=received_byte;
                        command_count=1;
                    end
                end else begin
                    command[command_count]=received_byte;
                    if(command_count==5) begin
                        if (command[5][0] !== 1'b1)
                            $fatal(1, "SD command end bit must be 1, final byte=%02x", command[5]);
                        command_count=0;
                        case(command[0][5:0])
                            0: begin
                                cmd0_count=cmd0_count+1;
                                responses[tail]=8'h01; tail=tail+1;
                            end
                            8: begin
                                responses[tail]=8'h01;
                                responses[tail+1]=0;
                                responses[tail+2]=0;
                                responses[tail+3]=1;
                                responses[tail+4]=8'haa;
                                tail=tail+5;
                            end
                            55: begin responses[tail]=8'h01; tail=tail+1; end
                            41: begin responses[tail]=0; tail=tail+1; end
                            17: begin
                                cmd17_count=cmd17_count+1;
                                command_lba={command[1],command[2],command[3],command[4]};
                                responses[tail]=8'hff;
                                responses[tail+1]=0;
                                responses[tail+2]=8'hff;
                                responses[tail+3]=8'hfe;
                                for(j=0;j<512;j=j+1)
                                    responses[tail+4+j]=disk[command_lba][j];
                                responses[tail+516]=8'h12;
                                responses[tail+517]=8'h34;
                                tail=tail+518;
                            end
                            default: begin
                                $display("ERROR: unexpected command %0d",command[0][5:0]);
                                errors=errors+1;
                            end
                        endcase
                    end else command_count=command_count+1;
                end
            end else bit_count=bit_count+1'b1;
        end
    end

    always @(posedge clk) if(rst_n) begin
        if(mem_wr_valid) begin
            if(mem_wr_addr<4) pixels[mem_wr_addr]<=mem_wr_data;
            else begin $display("ERROR: write address %0d",mem_wr_addr); errors=errors+1; end
            writes=writes+1;
        end
        if(source_done) write_fence<=1;
        read_response_valid<=read_valid;
        if(read_valid) read_response_data<=pixels[read_addr];
        if(master_write_valid) begin
            if(master_write_addr>=4 && master_write_addr<8)
                master_pixels[master_write_addr-4]<=master_write_data;
            else begin $display("ERROR: master address %0d",master_write_addr); errors=errors+1; end
            master_writes=master_writes+1;
        end
    end

    initial begin
        for(i=0;i<5;i=i+1) for(j=0;j<512;j=j+1) disk[i][j]=0;
        disk[0][450]=8'h0c; disk[0][454]=1;
        disk[1][11]=0; disk[1][12]=2; disk[1][13]=1;
        disk[1][14]=1; disk[1][16]=1; disk[1][36]=1; disk[1][44]=2;
        disk[3][0]=8'h49; disk[3][8]=8'h42; disk[3][9]=8'h4d;
        disk[3][10]=8'h50; disk[3][11]=8'h20;
        disk[3][26]=3; disk[3][28]=70; disk[3][32]=0;
        disk[4][0]=8'h42; disk[4][1]=8'h4d;
        disk[4][2]=70; disk[4][10]=54; disk[4][14]=40;
        disk[4][18]=2; disk[4][22]=2; disk[4][26]=1;
        disk[4][28]=24;
        disk[4][54]=0; disk[4][55]=0; disk[4][56]=255;
        disk[4][57]=255; disk[4][58]=0; disk[4][59]=0;
        disk[4][62]=0; disk[4][63]=255; disk[4][64]=0;
        disk[4][65]=255; disk[4][66]=255; disk[4][67]=255;
        if (SUPERFLOPPY) begin
            for (j=0;j<512;j=j+1) begin
                disk[0][j]=disk[1][j];
                disk[2][j]=disk[3][j];
                disk[3][j]=disk[4][j];
            end
            disk[0][0]=8'hEB;
            disk[0][510]=8'h55;
            disk[0][511]=8'hAA;
        end
        #22; rst_n=1;
        while(!cmd_ready && wait_count<500000) begin
            @(negedge clk); wait_count=wait_count+1;
        end
        if(!cmd_ready || catalog_count!=1)
            $fatal(1,"FAIL: SPI catalog timeout count=%0d code=%h",catalog_count,error_code);
        @(negedge clk); cmd_valid=1;
        @(negedge clk); cmd_valid=0;
        wait(dut.u_sector.state == 3'd4 &&
             dut.u_sector.lba_q == (SUPERFLOPPY ? 32'd3 : 32'd4));
        @(negedge clk);
        force dut.u_sector.serve_enable = 1'b0;
        held_sector_index = dut.u_sector.serve_index;
        repeat(20) begin
            @(negedge clk);
            if(dut.u_sector.din_valid ||
               dut.u_sector.serve_index != held_sector_index)
                $fatal(1,"FAIL: TF sector byte advanced during backpressure");
        end
        release dut.u_sector.serve_enable;
        wait_count=0;
        while(!source_done && !source_error && wait_count<500000) begin
            @(negedge clk); wait_count=wait_count+1;
        end
        if(!source_done || source_error || writes!=4 ||
           descriptor_width!=2 || descriptor_height!=2 ||
           pixels[0]!=32'h0000ff00 || pixels[1]!=32'h00ffffff ||
           pixels[2]!=32'h00ff0000 || pixels[3]!=32'h000000ff ||
           cmd0_count!=1 || cmd17_count!=4 ||
           deselected_clock_edges<144 || errors!=0)
            $fatal(1,"FAIL: TF SPI BMP done=%b err=%b writes=%0d cmd0=%0d cmd17=%0d code=%h",
                   source_done,source_error,writes,cmd0_count,cmd17_count,error_code);
        @(negedge clk); packet_start=1; packet_credit=2;
        @(negedge clk); packet_start=0; packet_credit=0;
        wait_count=0;
        while(!pending_swap && wait_count<300) begin
            @(negedge clk); wait_count=wait_count+1;
        end
        if(!pending_swap || master_writes!=4 || front_valid ||
           packet_source_error || protocol_error || commit_error)
            $fatal(1,"FAIL: SPI image packet candidate writes=%0d",master_writes);
        @(negedge clk); frame_boundary=1;
        @(negedge clk); frame_boundary=0;
        repeat(2) @(negedge clk);
        if(!front_valid || front_base!=4 || front_frame_id!=1 ||
           master_pixels[0]!=pixels[0] || master_pixels[1]!=pixels[1] ||
           master_pixels[2]!=pixels[2] || master_pixels[3]!=pixels[3])
            $fatal(1,"FAIL: SPI image Master front");
        $display("PASS: m2_slave_tf_media_core SPI-to-Master sectors=%0d pixels=%0d",
                 cmd17_count,master_writes);
        $finish;
    end
endmodule
