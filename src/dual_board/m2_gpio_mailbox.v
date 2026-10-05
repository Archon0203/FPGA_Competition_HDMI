// M2 board-to-board mailbox: 6 bundled-data bits + one word-start flag,
// with a four-phase request/acknowledge handshake.
//
// Each 32-bit word is transferred as six 7-bit symbols:
//   symbol 0: {1'b1, word[ 5: 0]}   -- explicit start-of-word marker
//   symbol 1: {1'b0, word[11: 6]}
//   symbol 2: {1'b0, word[17:12]}
//   symbol 3: {1'b0, word[23:18]}
//   symbol 4: {1'b0, word[29:24]}
//   symbol 5: {1'b0, 4'b0000, word[31:30]}
//
// Why this differs from the original 5-beat toggle mailbox:
//   * req/ack now return to zero after every symbol, so resetting either
//     endpoint cannot leave the toggle phase permanently inverted;
//   * every word carries an explicit start marker, so a receiver reset in the
//     middle of a word discards the partial word and re-locks at the next word;
//   * a transmitter reset first waits for ack==0 before accepting a new word,
//     so a stale receiver acknowledgement cannot silently consume symbol 0.
//
// Data is driven before req rises and remains stable until ack rises.  Only the
// handshake controls are synchronized; this remains a low-speed bundled-data
// bring-up link rather than a high-speed video PHY.
module m2_gpio_mailbox_tx(
    input wire clk, rst_n,
    input wire in_valid, input wire [31:0] in_data, output wire in_ready,
    output reg [6:0] data, output reg req, input wire ack);

    localparam [2:0] ST_ALIGN      = 3'd0;
    localparam [2:0] ST_READY      = 3'd1;
    localparam [2:0] ST_ASSERT_REQ = 3'd2;
    localparam [2:0] ST_WAIT_ACK1  = 3'd3;
    localparam [2:0] ST_WAIT_ACK0  = 3'd4;

    reg ack1, ack2;
    reg [31:0] word_q;
    reg [2:0] beat;
    reg [2:0] state;

    assign in_ready = (state == ST_READY) && (ack2 == 1'b0);

    function [6:0] symbol_for_beat;
        input [31:0] word_value;
        input [2:0]  beat_value;
        begin
            case (beat_value)
                3'd0: symbol_for_beat = {1'b1, word_value[5:0]};
                3'd1: symbol_for_beat = {1'b0, word_value[11:6]};
                3'd2: symbol_for_beat = {1'b0, word_value[17:12]};
                3'd3: symbol_for_beat = {1'b0, word_value[23:18]};
                3'd4: symbol_for_beat = {1'b0, word_value[29:24]};
                3'd5: symbol_for_beat = {1'b0, 4'b0000, word_value[31:30]};
                default: symbol_for_beat = 7'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack1   <= 1'b0;
            ack2   <= 1'b0;
            word_q <= 32'd0;
            beat   <= 3'd0;
            state  <= ST_ALIGN;
            data   <= 7'd0;
            req    <= 1'b0;
        end else begin
            ack1 <= ack;
            ack2 <= ack1;

            case (state)
                // A local reset always drives req low.  Do not accept payload
                // until the remote endpoint has also returned ack low.
                ST_ALIGN: begin
                    req <= 1'b0;
                    if (ack2 == 1'b0)
                        state <= ST_READY;
                end

                ST_READY: begin
                    req <= 1'b0;
                    if (ack2 != 1'b0) begin
                        // Receiver may have been left in the high-ack half of
                        // a transaction while this endpoint reset.
                        state <= ST_ALIGN;
                    end else if (in_valid) begin
                        word_q <= in_data;
                        beat   <= 3'd0;
                        data   <= {1'b1, in_data[5:0]};
                        state  <= ST_ASSERT_REQ;
                    end
                end

                ST_ASSERT_REQ: begin
                    // data was prepared at least one source clock earlier.
                    req   <= 1'b1;
                    state <= ST_WAIT_ACK1;
                end

                ST_WAIT_ACK1: begin
                    if (ack2 == 1'b1) begin
                        req   <= 1'b0;
                        state <= ST_WAIT_ACK0;
                    end
                end

                ST_WAIT_ACK0: begin
                    if (ack2 == 1'b0) begin
                        if (beat == 3'd5) begin
                            state <= ST_READY;
                        end else begin
                            beat  <= beat + 3'd1;
                            data  <= symbol_for_beat(word_q, beat + 3'd1);
                            state <= ST_ASSERT_REQ;
                        end
                    end
                end

                default: begin
                    req   <= 1'b0;
                    state <= ST_ALIGN;
                end
            endcase
        end
    end
endmodule

module m2_gpio_mailbox_rx(
    input wire clk, rst_n,
    input wire [6:0] data, input wire req, output reg ack,
    output reg out_valid, output reg [31:0] out_data, input wire out_ready);

    localparam ST_WAIT_REQ1 = 1'b0;
    localparam ST_WAIT_REQ0 = 1'b1;

    reg req1, req2;
    reg state;
    reg settle;
    reg assembling;
    reg [2:0] beat;
    reg [29:0] lower;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req1       <= 1'b0;
            req2       <= 1'b0;
            state      <= ST_WAIT_REQ1;
            settle     <= 1'b0;
            assembling <= 1'b0;
            beat       <= 3'd0;
            lower      <= 30'd0;
            ack        <= 1'b0;
            out_valid  <= 1'b0;
            out_data   <= 32'd0;
        end else begin
            req1 <= req;
            req2 <= req1;

            if (out_valid && out_ready)
                out_valid <= 1'b0;

            case (state)
                ST_WAIT_REQ1: begin
                    // Do not accept a new symbol while the completed word is
                    // back-pressured.  The transmitter will hold req high.
                    if (!out_valid && req2) begin
                        if (!settle) begin
                            // One extra destination cycle for bundled data to
                            // settle after the synchronized request edge.
                            settle <= 1'b1;
                        end else begin
                            settle <= 1'b0;

                            if (data[6]) begin
                                // Explicit word marker.  It intentionally
                                // re-starts assembly even if a previous word
                                // was interrupted by a one-sided reset.
                                lower[5:0] <= data[5:0];
                                beat       <= 3'd1;
                                assembling <= 1'b1;
                            end else if (assembling) begin
                                case (beat)
                                    3'd1: begin lower[11:6]  <= data[5:0]; beat <= 3'd2; end
                                    3'd2: begin lower[17:12] <= data[5:0]; beat <= 3'd3; end
                                    3'd3: begin lower[23:18] <= data[5:0]; beat <= 3'd4; end
                                    3'd4: begin lower[29:24] <= data[5:0]; beat <= 3'd5; end
                                    3'd5: begin
                                        // Upper four payload bits are padding;
                                        // only data[1:0] carry word[31:30].
                                        out_data   <= {data[1:0], lower};
                                        out_valid  <= 1'b1;
                                        assembling <= 1'b0;
                                        beat       <= 3'd0;
                                    end
                                    default: begin
                                        assembling <= 1'b0;
                                        beat       <= 3'd0;
                                    end
                                endcase
                            end
                            // Non-start symbols received while not assembling
                            // are deliberately acknowledged and discarded.
                            // This lets the link drain to the next word marker.
                            ack   <= 1'b1;
                            state <= ST_WAIT_REQ0;
                        end
                    end else if (!req2) begin
                        settle <= 1'b0;
                    end
                end

                ST_WAIT_REQ0: begin
                    if (!req2) begin
                        ack   <= 1'b0;
                        state <= ST_WAIT_REQ1;
                    end
                end
            endcase
        end
    end
endmodule
