// Commit image caption + image-info metadata on exactly the same safe boundary
// as the framebuffer bank switch. Metadata may arrive long before commit;
// until then the currently displayed caption/info remains unchanged.
module m2_caption_commit #(parameter integer CACHE_SLOTS=6)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_begin,
    input  wire [7:0]  load_image_id,
    input  wire        filename_valid,
    input  wire [87:0] filename_83,
    input  wire        image_info_valid,
    input  wire [15:0] image_width,
    input  wire [15:0] image_height,
    input  wire [5:0]  image_bpp,
    input  wire        commit_pulse,
    input  wire        cache_store_pulse,
    output reg  [7:0]  displayed_image_id,
    output reg  [87:0] displayed_filename_83,
    output reg  [15:0] displayed_image_width,
    output reg  [15:0] displayed_image_height,
    input wire [2:0] load_slot,
    input wire cached_commit,
    input wire [2:0] cached_slot,
    input wire [7:0] query_image_id,
    output reg cache_hit,
    output reg [2:0] cache_slot,
    output reg [CACHE_SLOTS-1:0] cache_valid,
    output reg  [5:0]  displayed_image_bpp
);
    reg [7:0] pending_image_id;
    reg [87:0] pending_filename_83;
    reg [15:0] pending_image_width;
    reg [15:0] pending_image_height;
    reg [5:0] pending_image_bpp;

    reg [7:0] bank_id[0:CACHE_SLOTS-1];
    reg [87:0] bank_name[0:CACHE_SLOTS-1];
    reg [15:0] bank_width[0:CACHE_SLOTS-1], bank_height[0:CACHE_SLOTS-1];
    reg [5:0] bank_bpp[0:CACHE_SLOTS-1];
    integer i,j;
    always @(*) begin
        cache_hit=0; cache_slot=0;
        for(j=0;j<CACHE_SLOTS;j=j+1)
            if(cache_valid[j] && bank_id[j]==query_image_id) begin
                cache_hit=1; cache_slot=j;
            end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cache_valid<=0;
            for(i=0;i<CACHE_SLOTS;i=i+1) begin
                bank_id[i]<=0; bank_name[i]<={11{8'h20}};
                bank_width[i]<=0; bank_height[i]<=0; bank_bpp[i]<=0;
            end
            pending_image_id <= 8'd0;
            pending_filename_83 <= {11{8'h20}};
            pending_image_width <= 16'd0;
            pending_image_height <= 16'd0;
            pending_image_bpp <= 6'd0;
            displayed_image_id <= 8'd0;
            displayed_filename_83 <= {11{8'h20}};
            displayed_image_width <= 16'd0;
            displayed_image_height <= 16'd0;
            displayed_image_bpp <= 6'd0;
        end else begin
            if (load_begin) begin
                if(load_slot<CACHE_SLOTS) cache_valid[load_slot]<=0;
                pending_image_id <= load_image_id;
                pending_filename_83 <= {11{8'h20}};
                pending_image_width <= 16'd0;
                pending_image_height <= 16'd0;
                pending_image_bpp <= 6'd0;
            end
            if (filename_valid)
                pending_filename_83 <= filename_83;
            if (image_info_valid) begin
                pending_image_width <= image_width;
                pending_image_height <= image_height;
                pending_image_bpp <= image_bpp;
            end

            if (cached_commit === 1'b1) begin
                displayed_image_id<=bank_id[cached_slot];
                displayed_filename_83<=bank_name[cached_slot];
                displayed_image_width<=bank_width[cached_slot];
                displayed_image_height<=bank_height[cached_slot];
                displayed_image_bpp<=bank_bpp[cached_slot];
            end else if ((cache_store_pulse === 1'b1) || commit_pulse) begin
                if(load_slot<CACHE_SLOTS) begin
                    cache_valid[load_slot]<=1;
                    bank_id[load_slot]<=pending_image_id;
                    bank_name[load_slot]<=filename_valid ? filename_83 : pending_filename_83;
                    bank_width[load_slot]<=image_info_valid ? image_width : pending_image_width;
                    bank_height[load_slot]<=image_info_valid ? image_height : pending_image_height;
                    bank_bpp[load_slot]<=image_info_valid ? image_bpp : pending_image_bpp;
                end
                // Defensive same-cycle cases: newly arriving metadata wins over
                // stale pending values. Normal hardware flow receives metadata
                // before the SDRAM fence / safe-frame commit.
                if (commit_pulse) begin
                    displayed_image_id <= load_begin ? load_image_id : pending_image_id;
                    displayed_filename_83 <= filename_valid ? filename_83 : pending_filename_83;
                    displayed_image_width <= image_info_valid ? image_width : pending_image_width;
                    displayed_image_height <= image_info_valid ? image_height : pending_image_height;
                    displayed_image_bpp <= image_info_valid ? image_bpp : pending_image_bpp;
                end
            end
        end
    end
endmodule
