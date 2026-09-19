module hdmi_official_baseline_source #(
 parameter integer HACTIVE=640,HFP=16,HSA=96,HBP=48,VACTIVE=480,VFP=10,VSA=2,VBP=33
)(input wire clk_pix,input wire rst,output reg axis_user,output reg axis_valid,output reg axis_last,output reg [23:0] axis_data);
 localparam integer HTOTAL=HACTIVE+HFP+HSA+HBP, VTOTAL=VACTIVE+VFP+VSA+VBP;
 localparam integer HBLANK=HTOTAL-HACTIVE, VBLANK=VTOTAL-VACTIVE;
 reg [11:0] col_cnt,line_cnt;
 wire active=(line_cnt>=VBLANK)&&(col_cnt>=HBLANK);
 wire [11:0] x=col_cnt-HBLANK;
 function [23:0] bar; input [11:0] px; begin
  if(px<80) bar=24'hFFFFFF; else if(px<160) bar=24'hFFFF00;
  else if(px<240) bar=24'h00FFFF; else if(px<320) bar=24'h00FF00;
  else if(px<400) bar=24'hFF00FF; else if(px<480) bar=24'hFF0000;
  else if(px<560) bar=24'h0000FF; else bar=24'h000000;
 end endfunction
 always @(posedge clk_pix or posedge rst) begin
  if(rst) begin col_cnt<=0; line_cnt<=0; axis_user<=0; axis_valid<=0; axis_last<=0; axis_data<=0; end
  else begin
   axis_user <= (line_cnt==VBLANK)&&(col_cnt==HBLANK);
   axis_valid <= active;
   axis_last <= active&&(col_cnt==HTOTAL-1);
   axis_data <= active ? bar(x) : 24'd0;
   if(col_cnt==HTOTAL-1) begin col_cnt<=0; if(line_cnt==VTOTAL-1) line_cnt<=0; else line_cnt<=line_cnt+1'b1; end
   else col_cnt<=col_cnt+1'b1;
  end
 end
endmodule
