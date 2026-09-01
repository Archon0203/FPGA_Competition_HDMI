`timescale 1ps / 1ps

// ================================================================
// P1-02A official protected-core integration / phase probe
//
// Chain:
//   P0 abstract memory request
//     -> sdram_adapter
//     -> apug011_core_wrapper
//     -> official protected sdr_as_ram / sdr_init_ref / sdr_wrrd
//     -> official IS42s32200 behavioral SDRAM model
//
// IMPORTANT:
//   The bundled IS42s32200 model is a -7 timing model (tCK=7ns, tRCD=21ns).
//   The vendor reference PLL uses 150 MHz, which is outside that external
//   model's declared tCK envelope.  Therefore this acceptance TB defaults to
//   125 MHz (8ns period), with a simulation-only global_def configured for
//   125 MHz.  This verifies protected-core functional/data integration; it is
//   NOT evidence that the final HX4S20C hardware timing is 125 MHz.
//
//   APUG011 v1.2 also warns that read data may shift by one clock for different
//   SDRAM hardware/frequency/phase.  SFT_OFFSET_PS is therefore parameterized;
//   the canonical run uses 180deg, and a companion .do sweeps 0/90/180/270deg.
//
// Vendor RTL/model files are never modified by this TB.
// ================================================================

module tb_sdram_adapter_apug011_official #(
    parameter integer HALF_CLK_PS   = 4000, // 125 MHz => 8ns period
    parameter integer SFT_OFFSET_PS = 4000  // 180 degrees at 125 MHz
);

    localparam integer INIT_TIMEOUT_CYCLES = 600000;
    localparam integer OP_TIMEOUT_CYCLES   = 20000;
    localparam integer MODEL_TCK_MIN_PS     = 7000;
    localparam integer MODEL_TRCD_MIN_PS    = 21000;

    reg clk;
    reg clk_sft;
    reg rst_n;

    reg         mem_wr_valid;
    reg [20:0]  mem_wr_addr;
    reg [31:0]  mem_wr_data;
    wire        mem_wr_ready;

    reg         mem_rd_valid;
    reg [20:0]  mem_rd_addr;
    wire        mem_rd_ready;
    wire        mem_rvalid;
    wire [31:0] mem_rdata;

    wire        App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din;
    wire [3:0]  App_wr_dm;
    wire        App_rd_en;
    wire [20:0] App_rd_addr;
    wire        Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire        Sdr_init_done;
    wire        Sdr_init_ref_vld;
    wire        Sdr_busy;
    wire        App_ref_req;

    wire        ready_for_traffic;
    wire        protocol_error;
    wire        provider_fault;
    wire        contention_seen;
    wire [15:0] read_outstanding_debug;
    wire [31:0] read_accept_count_debug;
    wire [31:0] write_accept_count_debug;
    wire [31:0] app_read_word_count_debug;
    wire [31:0] app_write_word_count_debug;

    wire        SDRAM_CLK;
    wire        SDR_RAS;
    wire        SDR_CAS;
    wire        SDR_WE;
    wire [1:0]  SDR_BA;
    wire [10:0] SDR_ADDR;
    wire [3:0]  SDR_DM;
    wire [31:0] SDR_DQ;

    integer errors;
    integer checks;
    integer cycles;
    reg [31:0] read_value;

    // Independent monitor for the two timing limits that matter to the bundled
    // IS42 -7 model.  These counters complement the model's own $display checks.
    integer model_tck_violation_count_debug;
    integer model_trcd_violation_count_debug;
    integer app_read_dm_violation_count_debug;
    integer phy_read_dqm_violation_count_debug;
    integer phy_read_command_count_debug;
    time last_sdram_posedge;
    time act_t0, act_t1, act_t2, act_t3;
    reg  act_v0, act_v1, act_v2, act_v3;

    initial begin
        clk = 1'b0;
        forever #HALF_CLK_PS clk = ~clk;
    end

    initial begin
        clk_sft = 1'b0;
        #SFT_OFFSET_PS;
        forever #HALF_CLK_PS clk_sft = ~clk_sft;
    end

    sdram_adapter #(
        .RESP_TAG_FIFO_DEPTH(32)
    ) dut_adapter (
        .clk                         (clk),
        .rst_n                       (rst_n),
        .mem_wr_valid                (mem_wr_valid),
        .mem_wr_addr                 (mem_wr_addr),
        .mem_wr_data                 (mem_wr_data),
        .mem_wr_ready                (mem_wr_ready),
        .mem_rd_valid                (mem_rd_valid),
        .mem_rd_addr                 (mem_rd_addr),
        .mem_rd_ready                (mem_rd_ready),
        .mem_rvalid                  (mem_rvalid),
        .mem_rdata                   (mem_rdata),
        .App_wr_en                   (App_wr_en),
        .App_wr_addr                 (App_wr_addr),
        .App_wr_din                  (App_wr_din),
        .App_wr_dm                   (App_wr_dm),
        .App_rd_en                   (App_rd_en),
        .App_rd_addr                 (App_rd_addr),
        .Sdr_rd_en                   (Sdr_rd_en),
        .Sdr_rd_dout                 (Sdr_rd_dout),
        .Sdr_init_done               (Sdr_init_done),
        .Sdr_init_ref_vld            (Sdr_init_ref_vld),
        .Sdr_busy                    (Sdr_busy),
        .App_ref_req                 (App_ref_req),
        .ready_for_traffic           (ready_for_traffic),
        .protocol_error              (protocol_error),
        .provider_fault              (provider_fault),
        .contention_seen             (contention_seen),
        .read_outstanding_debug      (read_outstanding_debug),
        .read_accept_count_debug     (read_accept_count_debug),
        .write_accept_count_debug    (write_accept_count_debug),
        .app_read_word_count_debug   (app_read_word_count_debug),
        .app_write_word_count_debug  (app_write_word_count_debug)
    );

    apug011_core_wrapper #(
        .SELF_REFRESH_OPEN(1)
    ) dut_core (
        .Sdr_clk          (clk),
        .Sdr_clk_sft      (clk_sft),
        .rst_n            (rst_n),
        .Sdr_init_done    (Sdr_init_done),
        .Sdr_init_ref_vld (Sdr_init_ref_vld),
        .Sdr_busy         (Sdr_busy),
        .App_ref_req      (App_ref_req),
        .App_wr_en        (App_wr_en),
        .App_wr_addr      (App_wr_addr),
        .App_wr_dm        (App_wr_dm),
        .App_wr_din       (App_wr_din),
        .App_rd_en        (App_rd_en),
        .App_rd_addr      (App_rd_addr),
        .Sdr_rd_en        (Sdr_rd_en),
        .Sdr_rd_dout      (Sdr_rd_dout),
        .SDRAM_CLK        (SDRAM_CLK),
        .SDR_RAS          (SDR_RAS),
        .SDR_CAS          (SDR_CAS),
        .SDR_WE           (SDR_WE),
        .SDR_BA           (SDR_BA),
        .SDR_ADDR         (SDR_ADDR),
        .SDR_DM           (SDR_DM),
        .SDR_DQ           (SDR_DQ)
    );

    IS42s32200 u_sdram_model (
        .Dq    (SDR_DQ),
        .Addr  (SDR_ADDR),
        .Ba    (SDR_BA),
        .Clk   (SDRAM_CLK),
        .Cke   (1'b1),
        .Cs_n  (1'b0),
        .Ras_n (SDR_RAS),
        .Cas_n (SDR_CAS),
        .We_n  (SDR_WE),
        .Dqm   (SDR_DM)
    );

    task check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %0s @ %0t", message, $time);
            end else begin
                $display("PASS: %0s", message);
            end
        end
    endtask

    // APUG011 official app_wrrd holds App_wr_dm=0000 during reads.
    // A non-zero value here can propagate to physical DQM and mask SDRAM DQ.
    always @(posedge clk) begin
        if (!rst_n) begin
            app_read_dm_violation_count_debug = 0;
        end else if (App_rd_en && (App_wr_dm !== 4'b0000)) begin
            app_read_dm_violation_count_debug = app_read_dm_violation_count_debug + 1;
            $display("TB_DQM: App_rd_en with App_wr_dm=%b @ %0t", App_wr_dm, $time);
        end
    end

    // Monitor commands on the same SDRAM clock edge used by the vendor model.
    // ACT: RAS=0,CAS=1,WE=1; READ/WRITE: RAS=1,CAS=0.
    always @(posedge SDRAM_CLK) begin
        if (!rst_n || !Sdr_init_done) begin
            last_sdram_posedge = 0;
            act_t0 = 0; act_t1 = 0; act_t2 = 0; act_t3 = 0;
            act_v0 = 0; act_v1 = 0; act_v2 = 0; act_v3 = 0;
        end else begin
            if (last_sdram_posedge != 0 && (($time - last_sdram_posedge) < MODEL_TCK_MIN_PS)) begin
                model_tck_violation_count_debug = model_tck_violation_count_debug + 1;
                $display("TB_TIMING: tCK violation delta=%0t ps @ %0t", $time-last_sdram_posedge, $time);
            end
            last_sdram_posedge = $time;

            if ((SDR_RAS === 1'b0) && (SDR_CAS === 1'b1) && (SDR_WE === 1'b1)) begin
                case (SDR_BA)
                    2'b00: begin act_t0 = $time; act_v0 = 1'b1; end
                    2'b01: begin act_t1 = $time; act_v1 = 1'b1; end
                    2'b10: begin act_t2 = $time; act_v2 = 1'b1; end
                    2'b11: begin act_t3 = $time; act_v3 = 1'b1; end
                endcase
            end

            if ((SDR_RAS === 1'b1) && (SDR_CAS === 1'b0)) begin
                if (SDR_WE === 1'b1) begin
                    phy_read_command_count_debug = phy_read_command_count_debug + 1;
                    if (SDR_DM !== 4'b0000) begin
                        phy_read_dqm_violation_count_debug = phy_read_dqm_violation_count_debug + 1;
                        $display("TB_DQM: physical READ command with SDR_DM=%b @ %0t", SDR_DM, $time);
                    end
                end
                case (SDR_BA)
                    2'b00: if (act_v0 && (($time-act_t0) < MODEL_TRCD_MIN_PS)) begin
                        model_trcd_violation_count_debug = model_trcd_violation_count_debug + 1;
                        $display("TB_TIMING: tRCD violation bank0 delta=%0t ps @ %0t", $time-act_t0, $time);
                    end
                    2'b01: if (act_v1 && (($time-act_t1) < MODEL_TRCD_MIN_PS)) begin
                        model_trcd_violation_count_debug = model_trcd_violation_count_debug + 1;
                        $display("TB_TIMING: tRCD violation bank1 delta=%0t ps @ %0t", $time-act_t1, $time);
                    end
                    2'b10: if (act_v2 && (($time-act_t2) < MODEL_TRCD_MIN_PS)) begin
                        model_trcd_violation_count_debug = model_trcd_violation_count_debug + 1;
                        $display("TB_TIMING: tRCD violation bank2 delta=%0t ps @ %0t", $time-act_t2, $time);
                    end
                    2'b11: if (act_v3 && (($time-act_t3) < MODEL_TRCD_MIN_PS)) begin
                        model_trcd_violation_count_debug = model_trcd_violation_count_debug + 1;
                        $display("TB_TIMING: tRCD violation bank3 delta=%0t ps @ %0t", $time-act_t3, $time);
                    end
                endcase
            end
        end
    end

    task wait_init;
        begin
            cycles = 0;
            while (!Sdr_init_done && cycles < INIT_TIMEOUT_CYCLES) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            check_true(Sdr_init_done, "official APUG011 initialization completed");
            if (!Sdr_init_done) begin
                $display("FAIL: APUG011 init timeout; aborting official-core test");
                $finish;
            end
            repeat (16) @(negedge clk);
            check_true(ready_for_traffic, "adapter reports ready after official APUG011 init");
        end
    endtask

    task do_write;
        input [20:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            mem_wr_addr  = addr;
            mem_wr_data  = data;
            mem_wr_valid = 1'b1;
            cycles = 0;
            while (!mem_wr_ready && cycles < OP_TIMEOUT_CYCLES) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            check_true(mem_wr_ready, "abstract write accepted by adapter/official core");
            @(negedge clk);
            mem_wr_valid = 1'b0;
            if (cycles >= OP_TIMEOUT_CYCLES) begin
                $display("FAIL: write timeout addr=%0d", addr);
                $finish;
            end
            repeat (12) @(negedge clk);
        end
    endtask

    task do_read;
        input [20:0] addr;
        output [31:0] data;
        begin
            data = 32'hxxxxxxxx;
            @(negedge clk);
            mem_rd_addr  = addr;
            mem_rd_valid = 1'b1;
            cycles = 0;
            while (!mem_rd_ready && cycles < OP_TIMEOUT_CYCLES) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            check_true(mem_rd_ready, "abstract read accepted by adapter/official core");
            @(negedge clk);
            mem_rd_valid = 1'b0;
            if (cycles >= OP_TIMEOUT_CYCLES) begin
                $display("FAIL: read accept timeout addr=%0d", addr);
                $finish;
            end

            cycles = 0;
            while (!mem_rvalid && cycles < OP_TIMEOUT_CYCLES) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (mem_rvalid)
                data = mem_rdata;
            check_true(mem_rvalid, "target-lane read response returned through adapter");
            $display("READBACK: addr=%0d data=0x%08h @ %0t", addr, data, $time);
            if (cycles >= OP_TIMEOUT_CYCLES) begin
                $display("FAIL: read response timeout addr=%0d", addr);
                $finish;
            end
            repeat (24) @(negedge clk);
        end
    endtask

    initial begin
        errors       = 0;
        checks       = 0;
        cycles       = 0;
        model_tck_violation_count_debug  = 0;
        model_trcd_violation_count_debug = 0;
        app_read_dm_violation_count_debug = 0;
        phy_read_dqm_violation_count_debug = 0;
        phy_read_command_count_debug = 0;
        last_sdram_posedge = 0;
        act_t0 = 0; act_t1 = 0; act_t2 = 0; act_t3 = 0;
        act_v0 = 0; act_v1 = 0; act_v2 = 0; act_v3 = 0;
        rst_n        = 1'b0;
        mem_wr_valid = 1'b0;
        mem_wr_addr  = 21'd0;
        mem_wr_data  = 32'd0;
        mem_rd_valid = 1'b0;
        mem_rd_addr  = 21'd0;

        $display("CONFIG: HALF_CLK_PS=%0d SFT_OFFSET_PS=%0d", HALF_CLK_PS, SFT_OFFSET_PS);

        repeat (20) @(negedge clk);
        rst_n = 1'b1;

        $display("CASE0: wait for official APUG011 protected-core initialization");
        wait_init();
        check_true(App_ref_req == 1'b0, "adapter leaves APUG011 self-refresh enabled");

        $display("CASE1: arbitrary word writes through 4-word masked micro-groups");
        do_write(21'd5, 32'h11223344);
        do_write(21'd8, 32'hA5A55A5A);
        check_true(write_accept_count_debug == 32'd2, "two abstract writes accepted");
        check_true(app_write_word_count_debug == 32'd8, "two writes expanded to eight APUG011 words");

        $display("CASE2: read back target lanes through official controller/model");
        do_read(21'd5, read_value);
        check_true(read_value === 32'h11223344, "readback addr 5 matches written data");
        do_read(21'd8, read_value);
        check_true(read_value === 32'hA5A55A5A, "readback addr 8 matches written data");
        check_true(read_accept_count_debug == 32'd2, "two abstract reads accepted");
        check_true(app_read_word_count_debug == 32'd8, "two reads expanded to eight APUG011 words");

        $display("CASE3: model timing envelope and final protocol/outstanding health");
        repeat (64) @(negedge clk);
        check_true(model_tck_violation_count_debug == 0, "SDRAM_CLK stays inside IS42 -7 tCK envelope");
        check_true(model_trcd_violation_count_debug == 0, "ACT-to-column stays inside IS42 -7 tRCD envelope");
        check_true(app_read_dm_violation_count_debug == 0, "App_wr_dm remains 0000 for every APUG011 read word");
        check_true(phy_read_command_count_debug > 0, "official core emitted physical SDRAM READ commands");
        check_true(phy_read_dqm_violation_count_debug == 0, "physical READ commands are not DQM-masked");
        check_true(read_outstanding_debug == 16'd0, "all accepted reads retired");
        check_true(protocol_error == 1'b0, "adapter protocol_error remains clear");
        check_true(provider_fault == 1'b0, "official provider never dropped init_done");
        check_true(!(App_rd_en && App_wr_en), "APUG011 read/write enables are mutually exclusive");

        if (errors == 0)
            $display("PASS: official APUG011 model-safe integration passed (checks=%0d, half=%0dps, sft=%0dps)", checks, HALF_CLK_PS, SFT_OFFSET_PS);
        else
            $display("FAIL: official APUG011 model-safe integration errors=%0d checks=%0d half=%0dps sft=%0dps", errors, checks, HALF_CLK_PS, SFT_OFFSET_PS);

        $finish;
    end

endmodule
