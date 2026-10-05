// ============================================================================
// M2 Slave OPEN dispatcher.
//
// Purpose:
//   * issue at most one standalone bootstrap OPEN(0) after a usable catalog
//     becomes available, so a Slave board can still display a picture alone;
//   * once a Master OPEN is observed for the current catalog epoch, suppress
//     any not-yet-issued bootstrap so the automatic OPEN(0) cannot overwrite
//     the Master's selection later;
//   * after bootstrap ownership is resolved, accept OPEN(image_id) only from
//     the Master control plane;
//   * retain one pending remote OPEN while the TF/FAT/BMP service is busy.
//
// This module intentionally contains no timer, FIFO or media datapath logic.
// A later remote OPEN replaces an older queued OPEN while cmd_ready is low,
// which matches the UI semantics: the newest user selection wins.
//
// bootstrap_issued is also used as the "bootstrap opportunity consumed" flag:
// a remote OPEN arriving before bootstrap dispatch sets it as well.  This is
// deliberate; it prevents a delayed catalog_valid from injecting OPEN(0) after
// a Master-selected image has already taken ownership.
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
    // catalog only when no Master OPEN is already pending/in flight.
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
            // A restart creates a new bootstrap opportunity only if the Master
            // does not already own the next OPEN transaction and no command
            // is already held valid.  This also prevents restart from cloning
            // a bootstrap that is waiting for cmd_ready.
            if (catalog_restart) begin
                bootstrap_issued <= cmd_valid || remote_queued ||
                                    remote_open_request;
            end

            // Last user request wins while the media service is occupied or
            // while another command is waiting for ready.  Any Master OPEN
            // consumes the current epoch's not-yet-issued bootstrap right.
            if (remote_open_request) begin
                remote_queued    <= 1'b1;
                queued_image_id  <= remote_open_image_id;
                bootstrap_issued <= 1'b1;
            end

            // Standard valid/ready source: once asserted, payload remains
            // stable until the media service actually accepts it.
            if (cmd_valid) begin
                if (cmd_ready) begin
                    cmd_valid     <= 1'b0;
                    cmd_is_remote <= 1'b0;
                end
            end else begin
                // Give an already queued request first priority.  If no old
                // queue entry exists, a request arriving in this same cycle
                // is dispatched directly instead of allowing bootstrap OPEN(0)
                // to slip in ahead of it.
                if (remote_queued || remote_open_request) begin
                    cmd_valid     <= 1'b1;
                    cmd_is_remote <= 1'b1;
                    if (remote_queued) begin
                        cmd_image_id <= queued_image_id;
                        // Preserve a newer request arriving as the old queue
                        // entry moves to the immutable valid/ready output.
                        remote_queued <= remote_open_request;
                    end else begin
                        cmd_image_id  <= remote_open_image_id;
                        remote_queued <= 1'b0;
                    end
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
