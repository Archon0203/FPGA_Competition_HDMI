// ================================================================
// 模块   : sd_reader
// 功能   : SD 卡 SPI 模式高层次读卡状态机。
//           初始化: CMD0 -> CMD8 -> CMD55+ACMD41(轮询) -> CMD17 单块读。
//           字节传输引擎: 每字节用 spi_start 单拍脉冲 + spi_done 握手。
//           输出 512B 数据流, 带超时与重试。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统/SD 时钟
//   - start               : 启动初始化+读块(单拍)
//   - block_addr[31:0]    : 目标块地址(LBA)
//   - spi_start/spi_din   : 字节 SPI 发送脉冲/数据(对接 sd_spi)
//   - spi_done/spi_dout   : 字节 SPI 完成/接收
//   - data_valid/data_out : 数据字节流输出
//   - done/ok             : 完成/成功
// 参数:
//   - DATA_BYTES          : 块字节数(默认 512)
//   - RETRY_MAX           : 最大重试次数(默认 3)
//   - TIMEOUT             : 单字节 SPI 超时时钟数(默认 1000)
// 说明   : SPI 传输接口为字节级, 顶层与 sd_spi 直接对接。
// 时钟域: clk 为 SD 读卡时钟域(clk_sdo)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡实现。
// ================================================================

module sd_reader #(
    parameter integer DATA_BYTES = 512,
    parameter integer RETRY_MAX  = 3,
    parameter integer TIMEOUT    = 1000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] block_addr,
    output reg         spi_start,
    output reg  [7:0]  spi_din,
    input  wire        spi_done,
    input  wire [7:0]  spi_dout,
    output reg         data_valid,
    output reg  [7:0]  data_out,
    output reg         done,
    output reg         ok
);

    localparam [3:0] S_IDLE=0, S_PREP=1, S_WAIT=2, S_HANDLE=3,
                     S_TOKEN=4, S_DATA=5, S_CRC=6, S_DONE=7, S_ABORT=8;

    reg [3:0] state;
    reg [3:0] dst;               // 读字节后的目标状态(S_TOKEN/DATA/CRC 等)
    reg [2:0] phase;             // 0=CMD0 1=CMD8 2=CMD55 3=ACMD41 4=CMD17
    reg [2:0] byte_n;
    reg [3:0] rs_left;
    reg [3:0] rs_n;
    reg [7:0] resp [0:5];
    reg [47:0] cmd_bytes;
    reg [7:0]  tx_byte;
    reg [7:0]  rx_byte;
    reg        is_read;           // 当前字节是读响应/数据(发送 0xFF)
    reg [1:0]  read_ctx;          // 0=读取响应 1=token 2=data 3=crc
    reg [31:0] timeout_cnt;
    reg [1:0]  retry_cnt;
    reg [31:0] data_cnt;

    function [7:0] cmd_byte_at;
        input [47:0] c;
        input [2:0]  n;
        begin
            cmd_byte_at = (c >> (40 - n*8)) & 8'hFF;
        end
    endfunction

    function [47:0] make_cmd;
        input [2:0] idx;
        input [31:0] arg;
        begin
            case (idx)
                3'd0: make_cmd = {8'h40, 32'h00000000, 8'h95};
                3'd1: make_cmd = {8'h48, 32'h000001AA, 8'h87};
                3'd2: make_cmd = {8'h77, 32'h00000000, 8'h65};
                3'd3: make_cmd = {8'h69, 32'h40000000, 8'h77};
                default: make_cmd = {8'h51, arg, 8'h00};   // CMD17
            endcase
        end
    endfunction

    task start_cmd;
        input [2:0] idx;
        input [31:0] arg;
        begin
            cmd_bytes <= make_cmd(idx, arg);
            byte_n    <= 3'd0;
            is_read   <= 1'b0;
            tx_byte   <= cmd_byte_at(make_cmd(idx, arg), 3'd0);
            state     <= S_PREP;
            timeout_cnt <= 32'd0;
        end
    endtask

    task start_read;
        input [1:0] ctx;
        begin
            is_read <= 1'b1;
            read_ctx<= ctx;
            tx_byte <= 8'hFF;
            state   <= S_PREP;
            timeout_cnt <= 32'd0;
        end
    endtask

    task retry;
        begin
            retry_cnt <= retry_cnt + 1'b1;
            if (retry_cnt >= RETRY_MAX) begin
                state <= S_ABORT;
            end else begin
                phase <= 3'd0;
                start_cmd(2'd0, 32'd0);
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; dst <= S_IDLE; phase <= 3'd0;
            byte_n <= 3'd0; rs_left <= 4'd0; rs_n <= 4'd0;
            spi_start <= 1'b0; spi_din <= 8'hFF;
            tx_byte <= 8'hFF; rx_byte <= 8'hFF;
            is_read <= 1'b0; read_ctx <= 2'd0;
            data_valid <= 1'b0; data_out <= 8'd0;
            done <= 1'b0; ok <= 1'b0; timeout_cnt <= 32'd0;
            retry_cnt <= 2'd0; data_cnt <= 32'd0;
        end else begin
            data_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        phase <= 3'd0; retry_cnt <= 2'd0;
                        cmd_bytes <= make_cmd(3'd0, 32'd0);
                        byte_n    <= 3'd0;
                        is_read   <= 1'b0;
                        tx_byte   <= cmd_byte_at(make_cmd(3'd0, 32'd0), 3'd0);
                        state     <= S_PREP;
                        timeout_cnt <= 32'd0;
                    end
                end
                S_PREP: begin
                    spi_start <= 1'b1;
                    spi_din   <= tx_byte;
                    state     <= S_WAIT;
                    timeout_cnt <= 32'd0;
                end
                S_WAIT: begin
                    spi_start <= 1'b0;
                    timeout_cnt <= timeout_cnt + 1'b1;
                    if (spi_done) begin
                        rx_byte <= spi_dout;
                        if (!is_read) begin
                            // 发送命令字节
                            if (byte_n >= 3'd5) begin
                                case (phase)
                                    3'd0: rs_left <= 4'd1;
                                    3'd1: rs_left <= 4'd5;
                                    3'd2: rs_left <= 4'd1;
                                    3'd3: rs_left <= 4'd1;
                                    default: rs_left <= 4'd1;
                                endcase
                                rs_n <= 4'd0;
                                start_read(2'd0);
                            end else begin
                                byte_n <= byte_n + 1'b1;
                                tx_byte <= cmd_byte_at(cmd_bytes, byte_n+1'b1);
                                state   <= S_PREP;
                                timeout_cnt <= 32'd0;
                            end
                        end else begin
                            // 读取字节
                            case (read_ctx)
                                2'd0: begin // 响应
                                    resp[rs_n] <= spi_dout;
                                    rs_n <= rs_n + 1'b1;
                                    if (rs_left <= 4'd1) begin
                                        state <= S_HANDLE;
                                    end else begin
                                        rs_left <= rs_left - 1'b1;
                                        tx_byte <= 8'hFF;
                                        state   <= S_PREP;
                                        timeout_cnt <= 32'd0;
                                    end
                                end
                                2'd1: begin // token
                                    if (spi_dout == 8'hFE) begin
                                        data_cnt <= 32'd0;
                                        start_read(2'd2);
                                    end else begin
                                        retry;
                                    end
                                end
                                2'd2: begin // data
                                    data_valid <= 1'b1; data_out <= spi_dout;
                                    data_cnt <= data_cnt + 1'b1;
                                    if (data_cnt >= DATA_BYTES-1) begin
                                        start_read(2'd3);
                                    end else begin
                                        tx_byte <= 8'hFF;
                                        state   <= S_PREP;
                                        timeout_cnt <= 32'd0;
                                    end
                                end
                                default: begin // crc -> 完成
                                    done <= 1'b1; ok <= 1'b1;
                                    state <= S_DONE;
                                end
                            endcase
                        end
                    end else if (timeout_cnt >= TIMEOUT) begin
                        retry;
                    end
                end
                S_HANDLE: begin
                    case (phase)
                        3'd0: begin
                            if (resp[0][0]) begin
                                phase <= 3'd1;
                                start_cmd(2'd1, 32'd0);
                            end else begin
                                retry;
                            end
                        end
                        3'd1: begin
                            if (resp[0][0] && resp[4] == 8'hAA) begin
                                phase <= 3'd2;
                                start_cmd(2'd2, 32'd0);
                            end else begin
                                retry;
                            end
                        end
                        3'd2: begin
                            phase <= 3'd3;
                            start_cmd(2'd3, 32'd0);
                        end
                        3'd3: begin
                            if (resp[0] == 8'h00) begin
                                phase <= 3'd4;
                                start_cmd(3'd4, block_addr); // CMD17
                            end else if (retry_cnt < RETRY_MAX) begin
                                retry_cnt <= retry_cnt + 1'b1;
                                phase <= 3'd2;
                                start_cmd(2'd2, 32'd0);
                            end else begin
                                state <= S_ABORT;
                            end
                        end
                        default: begin // CMD17
                            if (resp[0] == 8'h00) begin
                                start_read(2'd1);
                            end else begin
                                retry;
                            end
                        end
                    endcase
                end
                S_DONE: done <= 1'b1;
                S_ABORT: begin
                    if (retry_cnt < RETRY_MAX) begin
                        retry_cnt <= retry_cnt + 1'b1;
                        phase <= 3'd0;
                        start_cmd(2'd0, 32'd0);
                    end else begin
                        done <= 1'b1; ok <= 1'b0; state <= S_DONE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
