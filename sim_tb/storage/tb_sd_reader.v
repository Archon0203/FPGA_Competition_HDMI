`timescale 1ns/1ps

// ================================================================
// Testbench : tb_sd_reader
// 行为级"字节级 SD 卡模型"响应 CMD0/CMD8/CMD55/ACMD41/CMD17,
// CMD17 返回 512B 数据(0..255 循环) + 2 CRC。
// 验证: 初始化成功、读块数据顺序正确、ok=1。
// 结局: PASS / FAIL
// ================================================================

module tb_sd_reader;
    localparam DATA_BYTES = 512;
    localparam TOKEN_PAD   = 3;   // token 前额外输出 3 个 0xFF

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        start = 1'b0;
    reg  [31:0] block_addr = 32'd123;
    wire       spi_start;
    wire [7:0] spi_din;
    reg        spi_done = 1'b0;
    reg  [7:0] spi_dout = 8'hFF;
    wire       data_valid;
    wire [7:0] data_out;
    wire       done, ok;
    wire       sd_cs_n;

    sd_reader #(.DATA_BYTES(DATA_BYTES)) u_dut (
        .clk(clk), .rst_n(rst_n), .start(start), .block_addr(block_addr),
        .spi_start(spi_start), .spi_din(spi_din),
        .spi_done(spi_done), .spi_dout(spi_dout),
        .data_valid(data_valid), .data_out(data_out),
        .done(done), .ok(ok), .sd_cs_n(sd_cs_n)
    );

    always #5 clk = ~clk;

    // ---- 字节级 SD 卡模型 ----
    reg [7:0]  tx_buf [0:5];
    reg [3:0]  tx_cnt = 4'd0;
    reg [7:0]  resp_q [0:8];
    integer    q_h = 0, q_t = 0;
    reg        stream = 1'b0;
    reg [9:0]  data_idx = 10'd0;
    reg        spi_start_prev = 1'b0;
    integer    init_sclk_bytes = 0;
    integer    cmd0_count = 0;
    integer    cmd17_count = 0;
    reg [31:0] last_cmd17_arg = 32'd0;

    integer i;
    function [7:0] data_byte;
        input [9:0] idx;
        reg [9:0] v;
        begin
            if (idx < TOKEN_PAD) begin
                data_byte = 8'hFF;       // token 前等待字节
            end else if (idx == TOKEN_PAD) begin
                data_byte = 8'hFE;       // 数据令牌
            end else if (idx <= TOKEN_PAD + 512) begin
                v = idx - TOKEN_PAD - 1;
                data_byte = v[7:0];
            end else begin
                data_byte = 8'hAB;       // CRC 占位
            end
        end
    endfunction

    always @(posedge clk) begin
        spi_done <= 1'b0;
        if (spi_start && !spi_start_prev) begin
            if (sd_cs_n) init_sclk_bytes = init_sclk_bytes + 1;
            // 输出当前响应(先看队列, 再流式数据)
            if (q_h > q_t) begin
                spi_dout <= resp_q[q_t];
                q_t <= q_t + 1;
            end else if (stream) begin
                spi_dout <= data_byte(data_idx);
                data_idx <= data_idx + 1'b1;
                if (data_idx == TOKEN_PAD + 514) stream <= 1'b0;
            end else begin
                spi_dout <= 8'hFF;
            end
            // 仅累积命令字节(读响应为 0xFF 不累积)
            if (spi_din != 8'hFF) begin
                tx_buf[tx_cnt] <= spi_din;
                if (tx_cnt == 4'd5) begin
                    begin : decode
                        reg [5:0] cidx;
                        cidx = tx_buf[0] & 6'h3F;
                        if (cidx == 6'd0) begin       // CMD0
                            cmd0_count = cmd0_count + 1;
                            resp_q[q_h] <= 8'h01; q_h <= q_h + 1;
                        end else if (cidx == 6'd8) begin // CMD8
                            resp_q[q_h]   <= 8'h01;
                            resp_q[q_h+1] <= 8'h00;
                            resp_q[q_h+2] <= 8'h00;
                            resp_q[q_h+3] <= 8'h01;
                            resp_q[q_h+4] <= 8'hAA;
                            q_h <= q_h + 5;
                        end else if (cidx == 6'd55) begin // CMD55
                            resp_q[q_h] <= 8'h01; q_h <= q_h + 1;
                        end else if (cidx == 6'd41) begin // ACMD41
                            resp_q[q_h] <= 8'h00; q_h <= q_h + 1;
                        end else if (cidx == 6'd17) begin // CMD17
                            cmd17_count = cmd17_count + 1;
                            last_cmd17_arg <= {tx_buf[1], tx_buf[2], tx_buf[3], tx_buf[4]};
                            resp_q[q_h] <= 8'h00;        // R1 就绪
                            q_h <= q_h + 1;
                            stream <= 1'b1;
                            data_idx <= 10'd0;
                        end
                    end
                    tx_cnt <= 4'd0;
                end else begin
                    tx_cnt <= tx_cnt + 1'b1;
                end
            end
            spi_done <= 1'b1;
        end
        spi_start_prev <= spi_start;
    end

    integer errors = 0;
    integer checks = 0;
    integer got_cnt = 0;
    integer exp_byte = 0;
    integer k;

    always @(posedge clk) begin
        if (data_valid) begin
            if (data_out !== (exp_byte & 8'hFF)) begin
                $display("ERROR: data mismatch got=%0d exp=%0d", data_out, exp_byte & 8'hFF);
                errors = errors + 1;
            end
            exp_byte = exp_byte + 1;
            got_cnt = got_cnt + 1;
        end
    end


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

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        k = 0;
        while (!done && k < 20000) begin
            @(posedge clk);
            k = k + 1;
        end
        #1;
        check(done, 1, "done");
        check(ok, 1, "ok");
        check(got_cnt, DATA_BYTES, "data byte count");
        check(init_sclk_bytes >= 10, 1, "CS high dummy bytes >=10");
        check(cmd0_count, 1, "first init sends CMD0 once");
        check(last_cmd17_arg, block_addr, "CMD17 arg matches LBA");
        check(u_dut.initialized, 1, "initialized flag after first block");

        // 复用性：不复位，重新启动一次读块，done/ok 应重新产生且数据从 0 开始。
        got_cnt = 0;
        exp_byte = 0;
        // 行为模型队列/游标复位，模拟卡模型可重复应答。
        q_h = 0;
        q_t = 0;
        data_idx = 10'd0;
        stream = 1'b0;
        tx_cnt = 4'd0;
        spi_start_prev = 1'b0;
        block_addr = 32'd999;
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        @(negedge clk);   // 让 RTL 在启动沿完成非阻塞更新后再检测 done

        k = 0;
        while (!done && k < 20000) begin
            @(posedge clk);
            k = k + 1;
        end
        #1;
        check(done, 1, "second done");
        check(ok, 1, "second ok");
        check(got_cnt, DATA_BYTES, "second data byte count");
        check(cmd0_count, 1, "second read does not reinitialize card");
        check(cmd17_count, 2, "second read issues another CMD17");
        check(last_cmd17_arg, block_addr, "second CMD17 arg matches LBA");

        if (errors == 0)
            $display("PASS: sd_reader ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
