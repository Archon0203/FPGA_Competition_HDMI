// Simulation-only vendor boundaries; does not prove physical HDMI or SDRAM.
`timescale 1ns/1ps
module p1_hdmi_pll_50m_25_125 (
    input  wire refclk_50m,
    input  wire reset,
    output wire lock,
    output wire pixel_clk,
    output wire serial_clk
);
reg pix=0,serial=0;always @(posedge refclk_50m) pix<=~pix;always #4 serial=~serial;
assign lock=!reset;assign pixel_clk=pix;assign serial_clk=serial;
endmodule
module clk_pll(input refclk,reset,output extlock,clk0_out,clk1_out,clk2_out);
reg sdr=0;always #3.333 sdr=~sdr;
assign extlock=!reset;assign clk0_out=refclk;assign clk1_out=sdr;assign clk2_out=!sdr;
endmodule
module apug011_core_wrapper #(
    parameter integer SELF_REFRESH_OPEN = 1
) (
    input  wire         Sdr_clk,
    input  wire         Sdr_clk_sft,
    input  wire         rst_n,

    output wire         Sdr_init_done,
    output wire         Sdr_init_ref_vld,
    output wire         Sdr_busy,

    input  wire         App_ref_req,

    input  wire         App_wr_en,
    input  wire [20:0]  App_wr_addr,
    input  wire [3:0]   App_wr_dm,
    input  wire [31:0]  App_wr_din,

    input  wire         App_rd_en,
    input  wire [20:0]  App_rd_addr,
    output wire         Sdr_rd_en,
    output wire [31:0]  Sdr_rd_dout,

    output wire         SDRAM_CLK,
    output wire         SDR_RAS,
    output wire         SDR_CAS,
    output wire         SDR_WE,
    output wire [1:0]   SDR_BA,
    output wire [10:0]  SDR_ADDR,
    output wire [3:0]   SDR_DM,
    inout  wire [31:0]  SDR_DQ
);
reg [31:0] mem[0:2097151];reg [9:0] read_v=0;reg [31:0] read_d[0:9];
reg [31:0] dout=0;reg rv=0;integer k;
assign Sdr_init_done=rst_n;assign Sdr_init_ref_vld=0;assign Sdr_busy=0;
assign Sdr_rd_en=rv;assign Sdr_rd_dout=dout;
always @(posedge Sdr_clk) begin
 if(!rst_n) begin read_v<=0;rv<=0;dout<=0;end
 else begin
  rv<=read_v[9];dout<=read_d[9];read_v<={read_v[8:0],App_rd_en};read_d[0]<=mem[App_rd_addr];
  for(k=1;k<10;k=k+1) read_d[k]<=read_d[k-1];
  if(App_wr_en) begin
   if(!App_wr_dm[0])mem[App_wr_addr][7:0]<=App_wr_din[7:0];
   if(!App_wr_dm[1])mem[App_wr_addr][15:8]<=App_wr_din[15:8];
   if(!App_wr_dm[2])mem[App_wr_addr][23:16]<=App_wr_din[23:16];
   if(!App_wr_dm[3])mem[App_wr_addr][31:24]<=App_wr_din[31:24];
  end
 end
end
endmodule
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input [10:0] addr,
input [1:0] ba,inout [31:0] dq,input cs_n,dm0,dm1,dm2,dm3,cke);endmodule
module apug092_tx_wrapper #(
    parameter integer HACTIVE   = 1280,
    parameter integer HFP       = 110,
    parameter integer HSA       = 40,
    parameter integer HBP       = 220,
    parameter integer VACTIVE   = 720,
    parameter integer VFP       = 5,
    parameter integer VSA       = 5,
    parameter integer VBP       = 20,
    parameter integer VIDEO_VIC = 69,
    parameter integer IIC_SCL_DIV = 125
) (
    input  wire        pixel_clk,
    input  wire        serial_clk,
    input  wire        rst,

    input  wire        edid_read_trig,
    output wire        edid_read_valid,
    output wire [7:0]  edid_read_data,

    input  wire        axis_user,
    input  wire        axis_valid,
    input  wire        axis_last,
    input  wire [23:0] axis_data,
    output wire        axis_ready,

    input  wire        audio_valid,
    input  wire [23:0] audio_left_data,
    input  wire [23:0] audio_right_data,
    input  wire        acr_valid,
    input  wire [19:0] acr_cts,
    input  wire [19:0] acr_n,

    output wire        video_locked,
    output wire        ddc_scl,
    inout  wire        ddc_sda,

    output wire        tmds_ch0_p,
    output wire        tmds_ch1_p,
    output wire        tmds_ch2_p,
    output wire        tmds_clk_p
);
assign axis_ready=1;assign video_locked=!rst;assign edid_read_valid=0;assign edid_read_data=0;
assign ddc_scl=1;assign tmds_clk_p=pixel_clk;assign tmds_ch0_p=0;assign tmds_ch1_p=0;assign tmds_ch2_p=0;
endmodule
