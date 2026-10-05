// M2 HDMI reset/lock supervisor.
//
// The original M2 Master used the board-proven 20 ms PLL reset delay, but it
// declared a frame "published" without checking whether APUG092 had actually
// locked the video stream.  On real hardware this can produce the contradictory
// state "DISPLAY_PUBLISHED=1 while the monitor still reports no signal".
//
// This supervisor keeps the proven reset hold, waits for O_video_locked after
// reset release, and automatically re-runs the HDMI reset sequence if lock is
// never acquired or is lost for a sustained interval.  The video-lock input is
// synchronized before it is used by the 50 MHz control domain.
module m2_hdmi_lock_supervisor #(
    parameter integer RESET_HOLD_CYCLES   = 1_000_000,  // 20 ms @ 50 MHz
    parameter integer LOCK_WAIT_CYCLES    = 10_000_000, // 200 ms @ 50 MHz
    parameter integer UNLOCK_FILTER_CYCLES= 1_000_000   // 20 ms @ 50 MHz
)(
    input  wire clk,
    input  wire ext_rst_n,
    input  wire pll_lock,
    input  wire video_locked_async,
    output reg  hdmi_rst,
    output wire video_locked_sync,
    output wire video_ready,
    output reg  recovery_pulse
);
    localparam [1:0] ST_RESET     = 2'd0;
    localparam [1:0] ST_WAIT_LOCK = 2'd1;
    localparam [1:0] ST_RUN       = 2'd2;

    // Width 25 covers the production 10,000,000-cycle watchdog and keeps the
    // implementation simple/portable for the current TD Verilog flow.
    reg [24:0] count;
    reg [1:0]  state;
    reg lock_ff1, lock_ff2;

    initial begin
        count          = 25'd0;
        state          = ST_RESET;
        lock_ff1       = 1'b0;
        lock_ff2       = 1'b0;
        hdmi_rst       = 1'b1;
        recovery_pulse = 1'b0;
    end

    assign video_locked_sync = lock_ff2;
    assign video_ready       = (state == ST_RUN) && lock_ff2 && pll_lock && ext_rst_n;

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            lock_ff1 <= 1'b0;
            lock_ff2 <= 1'b0;
        end else if (hdmi_rst) begin
            // Never carry a stale APUG092 lock indication across an automatic
            // recovery reset.  The next RUN state must be earned by a fresh
            // post-reset lock acquisition.
            lock_ff1 <= 1'b0;
            lock_ff2 <= 1'b0;
        end else begin
            lock_ff1 <= video_locked_async;
            lock_ff2 <= lock_ff1;
        end
    end

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            count          <= 25'd0;
            state          <= ST_RESET;
            hdmi_rst       <= 1'b1;
            recovery_pulse <= 1'b0;
        end else begin
            recovery_pulse <= 1'b0;

            // Any PLL loss immediately restarts the proven reset sequence.
            if (!pll_lock) begin
                count    <= 25'd0;
                state    <= ST_RESET;
                hdmi_rst <= 1'b1;
            end else begin
                case (state)
                    ST_RESET: begin
                        hdmi_rst <= 1'b1;
                        // Match the board-proven P1-04C reset sequencer exactly:
                        // count RESET_HOLD_CYCLES full 50-MHz cycles with reset
                        // asserted, then release reset on the following rising
                        // edge.  Keeping this phase relationship unchanged is
                        // important for the 125-MHz serial PHY recovery timing.
                        if (RESET_HOLD_CYCLES == 0) begin
                            count    <= 25'd0;
                            state    <= ST_WAIT_LOCK;
                            hdmi_rst <= 1'b0;
                        end else if (count < RESET_HOLD_CYCLES) begin
                            count <= count + 1'b1;
                        end else begin
                            count    <= 25'd0;
                            state    <= ST_WAIT_LOCK;
                            hdmi_rst <= 1'b0;
                        end
                    end

                    ST_WAIT_LOCK: begin
                        hdmi_rst <= 1'b0;
                        if (lock_ff2) begin
                            count <= 25'd0;
                            state <= ST_RUN;
                        end else if ((LOCK_WAIT_CYCLES <= 1) ||
                                     (count >= LOCK_WAIT_CYCLES-1)) begin
                            // No APUG092 video lock: actively retry rather than
                            // leaving TMDS in a permanent no-signal state.
                            count          <= 25'd0;
                            state          <= ST_RESET;
                            hdmi_rst       <= 1'b1;
                            recovery_pulse <= 1'b1;
                        end else begin
                            count <= count + 1'b1;
                        end
                    end

                    ST_RUN: begin
                        hdmi_rst <= 1'b0;
                        if (lock_ff2) begin
                            count <= 25'd0;
                        end else if ((UNLOCK_FILTER_CYCLES <= 1) ||
                                     (count >= UNLOCK_FILTER_CYCLES-1)) begin
                            // Ignore short lock glitches, but recover from a
                            // sustained transmitter/video-lock loss.
                            count          <= 25'd0;
                            state          <= ST_RESET;
                            hdmi_rst       <= 1'b1;
                            recovery_pulse <= 1'b1;
                        end else begin
                            count <= count + 1'b1;
                        end
                    end

                    default: begin
                        count    <= 25'd0;
                        state    <= ST_RESET;
                        hdmi_rst <= 1'b1;
                    end
                endcase
            end
        end
    end
endmodule
