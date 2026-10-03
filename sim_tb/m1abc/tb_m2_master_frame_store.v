`timescale 1ns/1ps
module tb_m2_master_frame_store;
    reg clk=0, rst_n=0, line_valid=0, line_start=0, line_end=0;
    reg frame_end=0, protocol_error=0, frame_boundary=0;
    reg [31:0] line_data=0;
    reg [15:0] line_frame_id=0, line_index=0;
    reg [7:0] line_image_id=0;
    wire line_ready, mem_wr_valid, front_valid, pending_swap, commit_pulse, commit_error;
    wire [20:0] mem_wr_addr, front_base;
    wire [31:0] mem_wr_data;
    wire [15:0] front_frame_id;
    wire [7:0] front_image_id;
    reg [7:0] cycles=0;
    wire mem_wr_ready = cycles[1:0] != 2'd1;
    integer writes=0, errors=0, commits=0, faults=0;
    integer x,y;

    always #5 clk=~clk;
    m2_master_frame_store #(.WIDTH(4),.HEIGHT(3),.BASE_A(0),.BASE_B(12)) dut (
        .clk(clk),.rst_n(rst_n),.line_valid(line_valid),.line_data(line_data),
        .line_start(line_start),.line_end(line_end),.frame_end(frame_end),
        .line_frame_id(line_frame_id),.line_image_id(line_image_id),
        .line_index(line_index),.line_ready(line_ready),
        .protocol_error(protocol_error),.mem_wr_valid(mem_wr_valid),
        .mem_wr_addr(mem_wr_addr),.mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),.frame_boundary(frame_boundary),
        .front_base(front_base),.front_valid(front_valid),
        .front_frame_id(front_frame_id),.front_image_id(front_image_id),
        .pending_swap(pending_swap),.commit_pulse(commit_pulse),
        .commit_error(commit_error));

    always @(posedge clk) if (rst_n) begin
        cycles <= cycles + 1'b1;
        if (mem_wr_valid && mem_wr_ready) begin
            if (mem_wr_addr !== ((front_valid ? 0 : 12) + line_index*4 +
                                 (line_data & 32'hff))) begin
                $display("ERROR: write address %0d",mem_wr_addr); errors=errors+1;
            end
            writes=writes+1;
        end
        if (commit_pulse) commits=commits+1;
        if (commit_error) faults=faults+1;
    end

    task send_line;
        input [15:0] fid;
        input [7:0] iid;
        input [15:0] row;
        input final_row;
        integer col;
        begin
            for(col=0;col<4;col=col+1) begin
                @(negedge clk);
                line_valid=1; line_frame_id=fid; line_image_id=iid;
                line_index=row; line_data=col;
                line_start=(col==0); line_end=(col==3);
                frame_end=final_row && col==3;
                @(posedge clk);
                while(!line_ready) @(posedge clk);
            end
            @(negedge clk); line_valid=0; line_start=0; line_end=0; frame_end=0;
        end
    endtask

    task send_frame;
        input [15:0] fid;
        input [7:0] iid;
        begin
            send_line(fid,iid,0,0);
            send_line(fid,iid,1,0);
            send_line(fid,iid,2,1);
        end
    endtask

    task boundary;
        begin
            @(negedge clk); frame_boundary=1;
            @(negedge clk); frame_boundary=0;
            repeat(2) @(negedge clk);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        send_frame(7,2);
        if (!pending_swap || front_valid || writes!=12) begin
            $display("ERROR: frame published before boundary"); errors=errors+1;
        end
        boundary();
        if (!front_valid || front_base!=12 || front_frame_id!=7 ||
            front_image_id!=2 || commits!=1) begin
            $display("ERROR: first commit"); errors=errors+1;
        end
        send_line(8,3,0,0);
        send_line(8,3,1,0);
        @(negedge clk); protocol_error=1;
        @(negedge clk); protocol_error=0;
        boundary();
        if(front_base!=12 || pending_swap || commits!=1 || faults==0) begin
            $display("ERROR: partial frame polluted front"); errors=errors+1;
        end
        send_line(9,1,0,0);
        send_line(9,1,1,0);
        send_frame(10,1);
        boundary();
        if(front_base!=0 || front_frame_id!=10 || front_image_id!=1 || commits!=2) begin
            $display("ERROR: recovery frame commit"); errors=errors+1;
        end
        if(errors==0) $display("PASS: m2_master_frame_store commits=%0d writes=%0d",commits,writes);
        else $fatal(1,"FAIL: m2_master_frame_store errors=%0d",errors);
        $finish;
    end
endmodule
