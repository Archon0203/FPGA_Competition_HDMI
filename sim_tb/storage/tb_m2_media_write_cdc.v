`timescale 1ns/1ps
module tb_m2_media_write_cdc;
    reg media_clk=0, sdr_clk=0, rst_n=0;
    always #20 media_clk = ~media_clk;
    always #3.333 sdr_clk = ~sdr_clk;
    reg wr_valid=0, done=0, wr_ready_sdr=0, adapter_idle=0;
    reg [20:0] wr_addr=0;
    reg [31:0] wr_data=0;
    wire wr_ready_media, wr_valid_sdr, fenced;
    wire [20:0] wr_addr_sdr;
    wire [31:0] wr_data_sdr;
    integer accepted=0;
    integer fence_count=0;

    m2_media_write_cdc #(.FIFO_ADDR_WIDTH(2)) dut (
        .media_clk(media_clk), .media_rst_n(rst_n),
        .media_wr_valid(wr_valid), .media_wr_addr(wr_addr),
        .media_wr_data(wr_data), .media_wr_ready(wr_ready_media),
        .media_done(done), .sdr_fenced(fenced),
        .sdr_clk(sdr_clk), .sdr_rst_n(rst_n),
        .sdr_wr_valid(wr_valid_sdr), .sdr_wr_addr(wr_addr_sdr),
        .sdr_wr_data(wr_data_sdr), .sdr_wr_ready(wr_ready_sdr),
        .sdr_adapter_idle(adapter_idle));

    always @(posedge sdr_clk) begin
        if (rst_n) begin
            if (wr_valid_sdr && wr_ready_sdr) begin
                if (wr_addr_sdr !== accepted || wr_data_sdr !== (32'h12340000 + accepted))
                    $fatal(1, "write order/data mismatch at %0d", accepted);
                accepted = accepted + 1;
            end
            if (fenced) begin
                fence_count = fence_count + 1;
                if (!adapter_idle) $fatal(1, "fence while adapter busy");
                if (fence_count == 1 && accepted != 3)
                    $fatal(1, "first fence before three writes");
                if (fence_count == 2 && accepted != 5)
                    $fatal(1, "second fence before five total writes");
            end
        end
    end

    task send_word;
        input [20:0] addr;
        begin
            @(negedge media_clk);
            if (!wr_ready_media) $fatal(1, "unexpected full FIFO");
            wr_addr = addr;
            wr_data = 32'h12340000 + addr;
            wr_valid = 1;
            @(negedge media_clk);
            wr_valid = 0;
        end
    endtask

    task send_done;
        begin
            @(negedge media_clk) done=1;
            @(negedge media_clk) done=0;
        end
    endtask

    task wait_fence_count;
        input integer wanted;
        integer guard;
        begin
            guard = 0;
            while (fence_count < wanted && guard < 1000) begin
                @(posedge sdr_clk);
                guard = guard + 1;
            end
            if (fence_count != wanted) $fatal(1, "missing fence %0d", wanted);
        end
    endtask

    initial begin
        #100 rst_n=1;

        // Transaction 1: fence must wait for writes and adapter-idle.
        send_word(0); send_word(1); send_word(2); send_done();
        repeat (15) @(posedge sdr_clk);
        if (fence_count != 0 || accepted != 0) $fatal(1, "stalled writes fenced");
        @(negedge sdr_clk) wr_ready_sdr=1;
        wait (accepted == 3);
        repeat (15) @(posedge sdr_clk);
        if (fence_count != 0) $fatal(1, "adapter still busy");
        @(negedge sdr_clk) adapter_idle=1;
        wait_fence_count(1);
        repeat (5) @(posedge sdr_clk);
        if (fenced) $fatal(1, "fence must be a pulse, not sticky");

        // Transaction 2 proves the CDC can fence more than one image.
        @(negedge sdr_clk) adapter_idle=0;
        send_word(3); send_word(4); send_done();
        wait (accepted == 5);
        repeat (10) @(posedge sdr_clk);
        if (fence_count != 1) $fatal(1, "second frame fenced before adapter idle");
        @(negedge sdr_clk) adapter_idle=1;
        wait_fence_count(2);
        repeat (5) @(posedge sdr_clk);
        if (fenced) $fatal(1, "second fence must also be one cycle");

        $display("PASS: m2_media_write_cdc repeated transactions writes=%0d fences=%0d", accepted, fence_count);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "timeout");
    end
endmodule
