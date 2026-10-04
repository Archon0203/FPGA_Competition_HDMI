// ============================================================================
// M2 Slave OPEN dispatcher.
//
// Purpose:
//   * issue exactly one standalone bootstrap OPEN(0) after a usable catalog
//     becomes available, so a Slave board can still display a picture alone;
//   * after that bootstrap, accept OPEN(image_id) only from the Master control
//     plane;
//   * retain one pending remote OPEN while the TF/FAT/BMP service is busy.
//
// This module intentionally contains no timer, FIFO or media datapath logic.
// A later remote OPEN replaces an older queued OPEN while cmd_ready is low,
// which matches the UI semantics: the newest user selection wins.
// ============================================================================
module m2_open_dispatcher (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       catalog_valid,
    input  wire [7:0] catalog_count,
    input  wire       cmd_ready,

    input  wire       remote_open_request,
    input  wire [7:0] remote_open_image_id,

    // Pulse when the media/catalog layer is explicitly restarted after a
    // failure.  This re-arms the one-shot bootstrap for a newly rebuilt
    // catalog (for example: boot without TF, insert TF, automatic retry).
    input  wire       catalog_restart,

    output reg        cmd_valid,
    output reg  [7:0] cmd_image_id,
    output reg        cmd_is_remote,
    output reg        bootstrap_issued,
    output reg        remote_queued
);
    reg [7:0] queued_image_id;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_valid         <= 1'b0;
            cmd_image_id      <= 8'd0;
            cmd_is_remote     <= 1'b0;
            bootstrap_issued  <= 1'b0;
            remote_queued     <= 1'b0;
            queued_image_id   <= 8'd0;
        end else begin
            if (catalog_restart)
                bootstrap_issued <= 1'b0;

            // Last user request wins while the media service is occupied or
            // while another command is waiting for ready.
            if (remote_open_request) begin
                remote_queued   <= 1'b1;
                queued_image_id <= remote_open_image_id;
            end

            // Standard valid/ready source: once asserted, payload remains
            // stable until the media service actually accepts it.
            if (cmd_valid) begin
                if (cmd_ready) begin
                    cmd_valid     <= 1'b0;
                    cmd_is_remote <= 1'b0;
                end
            end else begin
                if (remote_queued) begin
                    cmd_valid       <= 1'b1;
                    cmd_image_id    <= queued_image_id;
                    cmd_is_remote   <= 1'b1;
                    remote_queued   <= 1'b0;
                end else if (catalog_valid && (catalog_count != 8'd0) &&
                             !bootstrap_issued) begin
                    cmd_valid        <= 1'b1;
                    cmd_image_id     <= 8'd0;
                    cmd_is_remote    <= 1'b0;
                    bootstrap_issued <= 1'b1;
                end
            end
        end
    end
endmodule
