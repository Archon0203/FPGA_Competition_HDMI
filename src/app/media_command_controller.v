// ============================================================================
// Master-board C-line media command controller.
//
// Converts debounced key events into high-level media intents.  It owns no
// framebuffer address, SDRAM request, TF transaction, or board-link signal.
// The integration coordinator consumes media_cmd_* and decides when a command
// can become a load/SPI transaction.
// ============================================================================

module media_command_controller #(
    parameter integer IMAGE_ID_WIDTH    = 8,
    parameter integer SLIDE_PERIOD_CLKS = 100
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Debounced events and stable switch levels from the C-line input layer.
    // KEY0: play/pause, KEY1: next, KEY2: previous, KEY3: local emergency UI.
    input  wire [3:0]                key_event,
    input  wire [3:0]                sw,

    // Catalog metadata supplied by the coordinator.  A nonzero count is
    // required before a media command can be issued.
    input  wire                      catalog_valid,
    input  wire [IMAGE_ID_WIDTH-1:0] catalog_count,

    // High-level command channel to the coordinator.
    input  wire                      media_cmd_ready,
    output wire                      media_cmd_valid,
    output wire [IMAGE_ID_WIDTH-1:0] media_cmd_image_id,
    output wire [1:0]                media_cmd_mode,

    // Master-board C-line state/configuration.  Pixel-domain snapshotting is
    // intentionally owned by the later integration wrapper.
    output reg  [IMAGE_ID_WIDTH-1:0] selected_image_id,
    output reg                       play_en,
    output reg                       emergency,
    output reg                       slide_tick,
    output reg  [1:0]                transition_mode,
    output reg  [7:0]                contrast,
    output reg  signed [7:0]         brightness,
    output reg                       osd_en,
    output wire                      beep_alert
);

    localparam [1:0] CMD_OPEN = 2'd0;
    localparam integer TIMER_WIDTH =
        (SLIDE_PERIOD_CLKS <= 1) ? 1 : $clog2(SLIDE_PERIOD_CLKS);

    reg [TIMER_WIDTH-1:0]            slide_counter;
    reg                              catalog_active;
    reg                              pending_valid;
    reg [IMAGE_ID_WIDTH-1:0]         pending_image_id;
    reg                              deferred_valid;
    reg [IMAGE_ID_WIDTH-1:0]         deferred_image_id;

    wire catalog_usable = catalog_valid && (catalog_count != {IMAGE_ID_WIDTH{1'b0}});
    wire catalog_rebased = selected_image_id >= catalog_count;

    wire manual_next = catalog_active && catalog_usable && !emergency && key_event[1];
    wire manual_prev = catalog_active && catalog_usable && !emergency &&
                       !key_event[1] && key_event[2];
    wire auto_advance = catalog_active && catalog_usable && play_en && !emergency &&
                        !key_event[0] && !key_event[3] && !key_event[1] && !key_event[2] &&
                        (slide_counter == SLIDE_PERIOD_CLKS - 1);
    wire selection_request = manual_next || manual_prev || auto_advance || catalog_rebased;

    function [IMAGE_ID_WIDTH-1:0] increment_image;
        input [IMAGE_ID_WIDTH-1:0] image_id;
        begin
            if (image_id >= catalog_count - 1'b1)
                increment_image = {IMAGE_ID_WIDTH{1'b0}};
            else
                increment_image = image_id + 1'b1;
        end
    endfunction

    function [IMAGE_ID_WIDTH-1:0] decrement_image;
        input [IMAGE_ID_WIDTH-1:0] image_id;
        begin
            if (image_id == {IMAGE_ID_WIDTH{1'b0}})
                decrement_image = catalog_count - 1'b1;
            else
                decrement_image = image_id - 1'b1;
        end
    endfunction

    reg [IMAGE_ID_WIDTH-1:0] requested_image_id;
    always @(*) begin
        if (catalog_rebased)
            requested_image_id = {IMAGE_ID_WIDTH{1'b0}};
        else if (manual_prev)
            requested_image_id = decrement_image(selected_image_id);
        else
            requested_image_id = increment_image(selected_image_id);
    end

    assign media_cmd_valid    = pending_valid;
    assign media_cmd_image_id = pending_image_id;
    assign media_cmd_mode     = CMD_OPEN;
    assign beep_alert         = emergency;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slide_counter    <= {TIMER_WIDTH{1'b0}};
            catalog_active   <= 1'b0;
            pending_valid    <= 1'b0;
            pending_image_id <= {IMAGE_ID_WIDTH{1'b0}};
            deferred_valid   <= 1'b0;
            deferred_image_id<= {IMAGE_ID_WIDTH{1'b0}};
            selected_image_id<= {IMAGE_ID_WIDTH{1'b0}};
            play_en          <= 1'b1;
            emergency        <= 1'b0;
            slide_tick       <= 1'b0;
            transition_mode  <= 2'd0;
            contrast         <= 8'd64;
            brightness       <= 8'sd0;
            osd_en           <= 1'b1;
        end else begin
            slide_tick      <= 1'b0;
            transition_mode <= sw[1:0];
            contrast        <= sw[3] ? 8'd128 : 8'd64;
            brightness      <= sw[2] ? 8'sd32 : 8'sd0;

            if (key_event[0])
                play_en <= ~play_en;
            if (key_event[3])
                emergency <= ~emergency;

            if (!catalog_usable) begin
                slide_counter     <= {TIMER_WIDTH{1'b0}};
                catalog_active    <= 1'b0;
                pending_valid     <= 1'b0;
                deferred_valid    <= 1'b0;
                selected_image_id <= {IMAGE_ID_WIDTH{1'b0}};
            end else if (!catalog_active) begin
                // A new catalog starts by requesting image zero exactly once.
                slide_counter      <= {TIMER_WIDTH{1'b0}};
                catalog_active     <= 1'b1;
                selected_image_id  <= {IMAGE_ID_WIDTH{1'b0}};
                pending_valid      <= 1'b1;
                pending_image_id   <= {IMAGE_ID_WIDTH{1'b0}};
                deferred_valid     <= 1'b0;
            end else begin
                if (manual_next || manual_prev || auto_advance || catalog_rebased ||
                    !play_en || emergency || key_event[0] || key_event[3]) begin
                    slide_counter <= {TIMER_WIDTH{1'b0}};
                end else begin
                    slide_counter <= slide_counter + 1'b1;
                end

                if (auto_advance)
                    slide_tick <= 1'b1;

                if (selection_request) begin
                    selected_image_id <= requested_image_id;
                end

                // valid/payload remain stable until the coordinator accepts a
                // command.  New user intent is coalesced into one deferred
                // command and emitted after the current handshake.
                if (pending_valid) begin
                    if (media_cmd_ready) begin
                        if (selection_request &&
                            (requested_image_id != pending_image_id)) begin
                            pending_valid    <= 1'b1;
                            pending_image_id <= requested_image_id;
                            deferred_valid   <= 1'b0;
                        end else if (deferred_valid) begin
                            pending_valid    <= 1'b1;
                            pending_image_id <= deferred_image_id;
                            deferred_valid   <= 1'b0;
                        end else begin
                            pending_valid <= 1'b0;
                        end
                    end else if (selection_request &&
                                 (requested_image_id != pending_image_id)) begin
                        deferred_valid    <= 1'b1;
                        deferred_image_id <= requested_image_id;
                    end
                end else if (selection_request) begin
                    pending_valid    <= 1'b1;
                    pending_image_id <= requested_image_id;
                end else if (deferred_valid) begin
                    pending_valid    <= 1'b1;
                    pending_image_id <= deferred_image_id;
                    deferred_valid   <= 1'b0;
                end
            end
        end
    end

endmodule
