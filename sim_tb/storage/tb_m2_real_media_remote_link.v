`timescale 1ns/1ps
module tb_m2_real_media_remote_link;
    reg clk=0, rst_n=0, cmd_valid=0, streaming=0;
    reg [7:0] cmd_image_id=0, disk[0:7][0:511];
    reg [2:0] sector_q=0; reg [8:0] sector_index=0;
    wire cmd_ready, sector_req, sector_consume_ready;
    wire [31:0] sector_lba;
    wire sector_ready=streaming, sector_din_valid=streaming && sector_consume_ready;
    wire [7:0] sector_din=disk[sector_q][sector_index];
    wire service_wr_valid, service_wr_ready, source_done, source_error;
    wire [20:0] service_wr_addr; wire [31:0] service_wr_data;
    wire catalog_valid; wire [7:0] catalog_count, error_code;
    wire [15:0] catalog_epoch, descriptor_width, descriptor_height;
    m2_real_media_service #(.WIDTH(2),.HEIGHT(2)) u_media(
      .clk(clk),.rst_n(rst_n),.scan_start(1'b0),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
      .cmd_image_id(cmd_image_id),.frame_base(21'd0),.sector_req(sector_req),.sector_lba(sector_lba),
      .sector_consume_ready(sector_consume_ready),.sector_ready(sector_ready),.sector_idle(!streaming),
      .sector_din_valid(sector_din_valid),.sector_din(sector_din),.sector_error(1'b0),
      .mem_wr_valid(service_wr_valid),.mem_wr_addr(service_wr_addr),.mem_wr_data(service_wr_data),
      .mem_wr_ready(service_wr_ready),.catalog_valid(catalog_valid),.catalog_count(catalog_count),
      .catalog_epoch(catalog_epoch),.descriptor_valid(),.descriptor_image_id(),.descriptor_width(descriptor_width),
      .descriptor_height(descriptor_height),.source_ready(),.source_busy(),.source_done(source_done),
      .source_error(source_error),.error_code(error_code));
    reg [31:0] slave_ram[0:3], master_ram[0:3];
    wire frame_valid,frame_ready,frame_busy; wire [31:0] frame_word;
    wire [6:0] gpio_data; wire gpio_req,gpio_ack,mailbox_valid,mailbox_ready; wire [31:0] mailbox_word;
    wire frame_done_master,frame_error_master,frame_wr_valid; wire [20:0] frame_wr_addr; wire [31:0] frame_wr_data;
    assign service_wr_ready=frame_ready;
    always #5 clk=~clk;
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin streaming<=0;sector_q<=0;sector_index<=0; end
      else if(!sector_req) begin streaming<=0;sector_index<=0; end
      else if(!streaming) begin streaming<=1;sector_q<=sector_lba[2:0];sector_index<=0; end
      else if(sector_consume_ready) begin if(sector_index==511) streaming<=0; else sector_index<=sector_index+1'b1; end
    end
    always @(posedge clk) if(rst_n && service_wr_valid && service_wr_ready) slave_ram[service_wr_addr]<=service_wr_data;
    m2_remote_frame_tx u_tx(.clk(clk),.rst_n(rst_n),.frame_begin(cmd_valid&&cmd_ready),.image_id(cmd_image_id),.wr_valid(service_wr_valid),.wr_addr(service_wr_addr),.wr_data(service_wr_data),.wr_ready(frame_ready),.frame_done(source_done),.frame_error(source_error),.out_valid(frame_valid),.out_data(frame_word),.out_ready(frame_ready),.busy(frame_busy));
    m2_gpio_mailbox_tx u_gpio_tx(.clk(clk),.rst_n(rst_n),.in_valid(frame_valid),.in_data(frame_word),.in_ready(frame_ready),.data(gpio_data),.req(gpio_req),.ack(gpio_ack));
    m2_gpio_mailbox_rx u_gpio_rx(.clk(clk),.rst_n(rst_n),.data(gpio_data),.req(gpio_req),.ack(gpio_ack),.out_valid(mailbox_valid),.out_data(mailbox_word),.out_ready(mailbox_ready));
    m2_remote_frame_rx #(.PIXELS(4)) u_rx(.clk(clk),.rst_n(rst_n),.in_valid(mailbox_valid),.in_data(mailbox_word),.in_ready(mailbox_ready),.frame_begin(),.frame_done(frame_done_master),.frame_error(frame_error_master),.image_id(),.wr_valid(frame_wr_valid),.wr_addr(frame_wr_addr),.wr_data(frame_wr_data),.wr_ready(1'b1),.busy());
    integer i,j,writes=0,master_writes=0,checks=0,errors=0,wait_count=0;
    always @(posedge clk) if(rst_n) begin if(service_wr_valid&&service_wr_ready) writes=writes+1; if(frame_wr_valid&&frame_wr_addr<4) begin master_ram[frame_wr_addr]<=frame_wr_data;master_writes=master_writes+1;end end
    task check; input cond; input [255:0] label; begin checks=checks+1;if(!cond)begin errors=errors+1;$display("ERROR: %0s",label);end end endtask
    initial begin
      for(i=0;i<8;i=i+1)for(j=0;j<512;j=j+1)disk[i][j]=0;
      disk[0][450]=8'h0c;disk[0][454]=1;disk[1][11]=0;disk[1][12]=2;disk[1][13]=1;disk[1][14]=1;disk[1][16]=1;disk[1][36]=1;disk[1][44]=2;
      disk[3][0]=8'h49;disk[3][8]="B";disk[3][9]="M";disk[3][10]="P";disk[3][26]=3;disk[3][28]=70;
      disk[4][0]="B";disk[4][1]="M";disk[4][2]=70;disk[4][10]=54;disk[4][14]=40;disk[4][18]=2;disk[4][22]=2;disk[4][26]=1;disk[4][28]=24;
      disk[4][54]=0;disk[4][55]=0;disk[4][56]=255;disk[4][57]=255;disk[4][58]=0;disk[4][59]=0;disk[4][62]=0;disk[4][63]=255;disk[4][64]=0;disk[4][65]=255;disk[4][66]=255;disk[4][67]=255;
      #22 rst_n=1;wait_count=0;while(!cmd_ready&&wait_count<10000)begin@(negedge clk);wait_count=wait_count+1;end
      check(cmd_ready&&catalog_valid&&catalog_count==1,"catalog ready");@(negedge clk)cmd_valid=1;@(negedge clk)cmd_valid=0;
      wait_count=0;while(!source_done&&!source_error&&wait_count<10000)begin@(negedge clk);wait_count=wait_count+1;end
      check(source_done&&!source_error&&writes==4,"Slave BMP frame");wait_count=0;while(!frame_done_master&&!frame_error_master&&wait_count<10000)begin@(negedge clk);wait_count=wait_count+1;end
      check(frame_done_master&&!frame_error_master&&master_writes==4,"Master receives frame");
      if(errors==0)$display("PASS: A-line TF -> Dupont -> Master checks=%0d",checks);else $fatal(1,"FAIL errors=%0d",errors);$finish;
    end
endmodule
