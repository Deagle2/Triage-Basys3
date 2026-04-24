`timescale 1ns / 1ps
//I made 3 tbs use any one of them, second one is same as first, clean er
module triage_top_tb;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst_n;
    reg        sample_valid;
    reg [11:0] hr_raw;
    reg [11:0] spo2_raw;
    reg [11:0] temp_raw;
    reg [11:0] resp_raw;

    wire        uart_tx_pin;
    wire [1:0]  led_priority;
    wire        led_red;
    wire        led_yellow;
    wire        led_green;

    // DUT Instance
    triage_top u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .hr_raw       (hr_raw),
        .spo2_raw     (spo2_raw),
        .temp_raw     (temp_raw),
        .resp_raw     (resp_raw),
        .uart_tx_pin  (uart_tx_pin),
        .led_priority (led_priority),
        .led_red      (led_red),
        .led_yellow   (led_yellow),
        .led_green    (led_green)
    );

    // Helper functions for logging
    function real q88_to_real;
        input signed [15:0] val;
        q88_to_real = $itor(val) / 256.0;
    endfunction

    function [47:0] pri_str;
        input [1:0] p;
        case (p)
            2'b00: pri_str = "GREEN ";
            2'b01: pri_str = "YELLOW";
            2'b10: pri_str = "RED   ";
            default: pri_str = "??????";
        endcase
    endfunction

    function [47:0] cause_str;
        input [1:0] c;
        case (c)
            2'b00: cause_str = "normal";
            2'b01: cause_str = "YELLOW";
            2'b10: cause_str = "RED   ";
            default: cause_str = "??????";
        endcase
    endfunction

    task run_tc;
        input [31:0]  tc_label;
        input integer hr_bpm_in;
        input real    temp_c_in;
        input integer spo2_pct_in;
        input [11:0]  hr_adc_in;
        input [11:0]  temp_adc_in;
        input [11:0]  spo2_adc_in;
        input [47:0]  expected_str;
        integer wait_cnt;
        reg [1:0] hr_c, temp_c, spo2_c;
        begin
            $display("----------------------------------------------------------");
            $display("[%0t ns] [STIM] %s | HR=%0d Temp=%.1fC SpO2=%0d%%  Expected=%s",
                     $time, tc_label, hr_bpm_in, temp_c_in, spo2_pct_in, expected_str);

            hr_raw       = hr_adc_in;
            temp_raw     = temp_adc_in;
            spo2_raw     = spo2_adc_in;
            resp_raw     = 12'h400; // Baseline Respiration
            sample_valid = 1'b1;
            @(posedge clk); #1;
            sample_valid = 1'b0;

            // Wait for internal Normalization valid
            wait_cnt = 0;
            while (!u_dut.norm_valid && wait_cnt < 20) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            
            // Wait for MLP Output Valid
            wait_cnt = 0;
            while (!u_dut.out_valid[0] && wait_cnt < 50) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            
            // Allow pipeline to settle for Priority Encoder
            repeat(5) @(posedge clk); #1;

            hr_c   = u_dut.cause_byte[5:4];
            temp_c = u_dut.cause_byte[3:2];
            spo2_c = u_dut.cause_byte[1:0];

            $display("[%0t ns] [MLP ] PRIORITY=%s  Confidence=%0d", $time, pri_str(led_priority), u_dut.confidence);
            $display("             CAUSE: HR=%s  Temp=%s  SpO2=%s", cause_str(hr_c), cause_str(temp_c), cause_str(spo2_c));

            // UART transmission simulation (Wait for start bit then skip ahead)
            wait_cnt = 0;
            while (uart_tx_pin == 1'b1 && wait_cnt < 5000) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            repeat(35000) @(posedge clk); #1; // Wait for full packet to transmit

            if (pri_str(led_priority) == expected_str)
                $display("[%0t ns] [PASS] Label matched expected.", $time);
            else
                $display("[%0t ns] [FAIL] Expected %s but got %s", $time, expected_str, pri_str(led_priority));

            repeat(50) @(posedge clk);
        end
    endtask

    initial begin
        // Reset sequence
        rst_n = 1'b0; sample_valid = 1'b0;
        hr_raw = 0; temp_raw = 0; spo2_raw = 0; resp_raw = 0;
        repeat(20) @(posedge clk); #1;
        rst_n = 1'b1;
        repeat(10) @(posedge clk); #1;

        $display("==========================================================");
        $display("   Triage System Phase 5 - Hackathon Test Suite");
        $display("==========================================================");

        // --- GREEN CASES ---
        // Raw 12 bit ADC values [Formula]
        // TC1: Healthy (72 bpm, 36.6C, 99%)
        run_tc("TC1", 72, 36.6, 99, 12'd1339, 12'd1331, 12'd3890, "GREEN ");
        // TC2: Healthy (75 bpm, 36.5C, 100%)
        run_tc("TC2", 75, 36.5, 100, 12'd1395, 12'd1280, 12'd4095, "GREEN ");
        // TC3: Mild tachycardia (110 bpm, 37C, 98%)
        run_tc("TC3", 110, 37.0, 98, 12'd2048, 12'd1536, 12'd3686, "GREEN ");

        // --- YELLOW CASES ---
        // TC4: Fever (80 bpm, 38.0C, 98%)
        run_tc("TC4", 80, 38.0, 98, 12'd1489, 12'd2048, 12'd3686, "YELLOW");
        // TC5: Mild Hypoxia (80 bpm, 37C, 92%)
        run_tc("TC5", 80, 37.0, 92, 12'd1489, 12'd1536, 12'd2457, "YELLOW");
        // TC6: Combined Mild (110 bpm, 38.0C, 94%)
        run_tc("TC6", 110, 38.0, 94, 12'd2048, 12'd2048, 12'd2867, "YELLOW");

        // --- RED CASES ---
        // TC7: Severe Tachycardia (150 bpm, 37C, 98%)
        run_tc("TC7", 150, 37.0, 98, 12'd2792, 12'd1536, 12'd3686, "RED   ");
        // TC8: High Fever (80 bpm, 39.5C, 98%)
        run_tc("TC8", 80, 39.5, 98, 12'd1489, 12'd2815, 12'd3686, "RED   ");
        // TC9: Severe Hypoxia (80 bpm, 37C, 82%)
        run_tc("TC9", 80, 37.0, 82, 12'd1489, 12'd1536, 12'd410,  "RED   ");
        // TC10: Critical System Failure (150 bpm, 39.5C, 82%)
        run_tc("TC10", 150, 39.5, 82, 12'd2792, 12'd2815, 12'd410,  "RED   ");

        $display("==========================================================");
        $display("   Test Finished");
        $display("==========================================================");
        $finish;
    end

    // Timeout
    initial begin
        #400_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule



/*// =============================================================================
// Module      : triage_top_tb
// Project     : Edge AI Hospital Emergency Triage - Phase 5 (HR+Temp+SpO2)
//
// BEFORE RUNNING:
//   set_property -name {xsim.simulate.runtime} -value {200ms} -objects [get_filesets sim_1]
//   close_sim
//   launch_simulation
//
// ADC conversions:
//   hr_raw   = round(hr_bpm / 220 * 4095)
//   temp_raw = round((temp_C - 34.0) / 8.0 * 4095)
//   spo2_raw = round((spo2_pct - 50.0) / 50.0 * 4095)
// =============================================================================
// =============================================================================
// Module      : triage_top_tb
// Project     : Edge AI Hospital Emergency Triage - Phase 5 (HR+Temp+SpO2)
//
// BEFORE RUNNING:
//   set_property -name {xsim.simulate.runtime} -value {200ms} -objects [get_filesets sim_1]
//   close_sim
//   launch_simulation
//
// ADC conversions (MUST match triage_vital_normaliser.sv exactly):
//   hr_raw   = round(hr_bpm / 220 * 4095)
//   temp_raw = round((temp_C - 34.0) / 8.0 * 4095)
//   spo2_raw = round((spo2_pct - 80.0) / 20.0 * 4095)
//
// Pre-computed ADC values:
//   HR:   80bpm=0x5D1  110bpm=0x800  150bpm=0xAE8  35bpm=0x28C  220bpm=0xFFF
//   Temp: 36.5C=0x500  37.0C=0x600  38.0C=0x800  39.5C=0xB00  34.5C=0x100
//   SpO2: 98%=0xE66    94%=0xB33    92%=0x999    82%=0x19A    100%=0xFFF
// =============================================================================
`timescale 1ns / 1ps

module triage_top_tb;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst_n;
    reg        sample_valid;
    reg [11:0] hr_raw;
    reg [11:0] spo2_raw;
    reg [11:0] temp_raw;
    reg [11:0] resp_raw;

    wire        uart_tx_pin;
    wire [1:0]  led_priority;
    wire        led_red;
    wire        led_yellow;
    wire        led_green;

    triage_top u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .hr_raw       (hr_raw),
        .spo2_raw     (spo2_raw),
        .temp_raw     (temp_raw),
        .resp_raw     (resp_raw),
        .uart_tx_pin  (uart_tx_pin),
        .led_priority (led_priority),
        .led_red      (led_red),
        .led_yellow   (led_yellow),
        .led_green    (led_green)
    );

    function real q88_to_real;
        input signed [15:0] val;
        q88_to_real = $itor(val) / 256.0;
    endfunction

    function [47:0] pri_str;
        input [1:0] p;
        case (p)
            2'b00: pri_str = "GREEN ";
            2'b01: pri_str = "YELLOW";
            2'b10: pri_str = "RED   ";
            default: pri_str = "??????";
        endcase
    endfunction

    function [47:0] cause_str;
        input [1:0] c;
        case (c)
            2'b00: cause_str = "normal";
            2'b01: cause_str = "YELLOW";
            2'b10: cause_str = "RED   ";
            default: cause_str = "??????";
        endcase
    endfunction

    task run_tc;
        input [23:0]  tc_label;
        input integer hr_bpm_in;
        input real    temp_c_in;
        input integer spo2_pct_in;
        input [11:0]  hr_adc_in;
        input [11:0]  temp_adc_in;
        input [11:0]  spo2_adc_in;
        input [47:0]  expected_str;
        integer wait_cnt;
        reg [1:0] hr_c, temp_c, spo2_c;
        begin
            $display("----------------------------------------------------------");
            $display("[%0t ns] [STIM] %s | HR=%0d Temp=%.1fC SpO2=%0d%%  Expected=%s",
                     $time, tc_label, hr_bpm_in, temp_c_in, spo2_pct_in, expected_str);

            hr_raw       = hr_adc_in;
            temp_raw     = temp_adc_in;
            spo2_raw     = spo2_adc_in;
            resp_raw     = 12'h400;
            sample_valid = 1'b1;
            @(posedge clk); #1;
            sample_valid = 1'b0;

            // Wait norm_valid
            wait_cnt = 0;
            while (!u_dut.norm_valid && wait_cnt < 10) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            @(posedge clk); #1;
            $display("[%0t ns] [NORM] HR=%0d(%.3f) Temp=%0d(%.3f) SpO2=%0d(%.3f)",
                     $time,
                     u_dut.norm_data[0], q88_to_real(u_dut.norm_data[0]),
                     u_dut.norm_data[1], q88_to_real(u_dut.norm_data[1]),
                     u_dut.norm_data[2], q88_to_real(u_dut.norm_data[2]));

            // Wait output valid
            wait_cnt = 0;
            while (!u_dut.out_valid[0] && wait_cnt < 20) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            @(posedge clk); #1;
            $display("[%0t ns] [OUTL] GREEN=%0d(%.3f) YELLOW=%0d(%.3f) RED=%0d(%.3f)",
                     $time,
                     u_dut.out_scores[0], q88_to_real(u_dut.out_scores[0]),
                     u_dut.out_scores[1], q88_to_real(u_dut.out_scores[1]),
                     u_dut.out_scores[2], q88_to_real(u_dut.out_scores[2]));

            // Wait enc_valid (2 cycle delay)
            wait_cnt = 0;
            while (!u_dut.enc_valid && wait_cnt < 10) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;

            hr_c   = u_dut.cause_byte[5:4];
            temp_c = u_dut.cause_byte[3:2];
            spo2_c = u_dut.cause_byte[1:0];

            $display("[%0t ns] [PENC] PRIORITY=%s  confidence=%0d",
                     $time, pri_str(led_priority), u_dut.confidence);
            $display("              CAUSE: HR=%s  Temp=%s  SpO2=%s",
                     cause_str(hr_c), cause_str(temp_c), cause_str(spo2_c));

            // Wait UART (4 bytes x 10 bits x 868 clocks = 34720 cycles)
            wait_cnt = 0;
            while (uart_tx_pin == 1'b1 && wait_cnt < 2000) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            repeat(35000) @(posedge clk); #1;

            $display("[%0t ns] [LED ] red=%b yellow=%b green=%b",
                     $time, led_red, led_yellow, led_green);

            if (pri_str(led_priority) == expected_str)
                $display("[%0t ns] [PASS] Expected=%s  Got=%s",
                         $time, expected_str, pri_str(led_priority));
            else
                $display("[%0t ns] [FAIL] Expected=%s  Got=%s",
                         $time, expected_str, pri_str(led_priority));

            repeat(20) @(posedge clk);
        end
    endtask

    initial begin
        rst_n        = 1'b0;
        sample_valid = 1'b0;
        hr_raw       = 12'h000;
        temp_raw     = 12'h000;
        spo2_raw     = 12'h000;
        resp_raw     = 12'h000;

        repeat(10) @(posedge clk); #1;
        rst_n = 1'b1;
        repeat(5)  @(posedge clk); #1;

        $display("==========================================================");
        $display("  triage_top - Phase 5: HR + Temp + SpO2");
        $display("  Network: 3->16->3  +  Cause classification");
        $display("  ADC: hr=bpm/220*4095  temp=(C-34)/8*4095  spo2=(pct-80)/20*4095");
        $display("==========================================================");

        // ---------------------------------------------------------------
// GREEN cases - all vitals normal (or borderline but not urgent)
// ---------------------------------------------------------------

// TC1: perfectly healthy patient (72, 36.6, 99)
run_tc("TC1", 72, 36.6, 99, 12'd1344, 12'd1331, 12'd3840, "GREEN ");

// TC2: normal HR, normal temp, perfect SpO2 (75, 36.5, 100)
run_tc("TC2", 75, 36.5, 100, 12'd1381, 12'd1280, 12'd4095, "GREEN ");

// TC3: mild tachycardia, others normal (110, 37.0, 98) → still GREEN
run_tc("TC3", 110, 37.0, 98, 12'd2048, 12'd1536, 12'd3686, "GREEN ");


// ---------------------------------------------------------------
// YELLOW cases - one vital mildly abnormal
// ---------------------------------------------------------------

// TC4: mild fever, others normal (80, 38.0, 98)
run_tc("TC4", 80, 38.0, 98, 12'd1489, 12'd2048, 12'd3686, "YELLOW");

// TC5: mild hypoxia, others normal (80, 37.0, 92)
run_tc("TC5", 80, 37.0, 92, 12'd1489, 12'd1536, 12'd2457, "YELLOW");

// TC6: all three mildly abnormal (110, 38.0, 94)
run_tc("TC6", 110, 38.0, 94, 12'd2048, 12'd2048, 12'd2867, "YELLOW");


// ---------------------------------------------------------------
// RED cases - at least one vital critically abnormal
// ---------------------------------------------------------------

// TC7: severe tachycardia only (150, 37.0, 98)
run_tc("TC7", 150, 37.0, 98, 12'd2856, 12'd1536, 12'd3686, "RED   ");

// TC8: high fever only (80, 39.5, 98)
run_tc("TC8", 80, 39.5, 98, 12'd1489, 12'd2816, 12'd3686, "RED   ");

// TC9: severe hypoxia only (80, 37.0, 82)
run_tc("TC9", 80, 37.0, 82, 12'd1489, 12'd1536, 12'd410,  "RED   ");

// TC10: all vitals critically abnormal (150, 39.5, 82)
run_tc("TC10", 150, 39.5, 82, 12'd2856, 12'd2816, 12'd410,  "RED   ");


        $display("==========================================================");
        $display("  All test cases complete.");
        $display("==========================================================");
        $finish;
    end

    initial begin
        #300_000_000;
        $display("*** WATCHDOG: exceeded 300ms ***");
        $finish;
    end

endmodule
*/
/*`timescale 1ns / 1ps



module triage_top_tb;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst_n;
    reg        sample_valid;
    reg [11:0] hr_raw;
    reg [11:0] spo2_raw;
    reg [11:0] temp_raw;
    reg [11:0] resp_raw;

    wire        uart_tx_pin;
    wire [1:0]  led_priority;
    wire        led_red;
    wire        led_yellow;
    wire        led_green;

    triage_top u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .hr_raw       (hr_raw),
        .spo2_raw     (spo2_raw),
        .temp_raw     (temp_raw),
        .resp_raw     (resp_raw),
        .uart_tx_pin  (uart_tx_pin),
        .led_priority (led_priority),
        .led_red      (led_red),
        .led_yellow   (led_yellow),
        .led_green    (led_green)
    );

    function real q88_to_real;
        input signed [15:0] val;
        q88_to_real = $itor(val) / 256.0;
    endfunction

    function [47:0] pri_str;
        input [1:0] p;
        case (p)
            2'b00: pri_str = "GREEN ";
            2'b01: pri_str = "YELLOW";
            2'b10: pri_str = "RED   ";
            default: pri_str = "??????";
        endcase
    endfunction

    function [47:0] cause_str;
        input [1:0] c;
        case (c)
            2'b00: cause_str = "normal";
            2'b01: cause_str = "YELLOW";
            2'b10: cause_str = "RED   ";
            default: cause_str = "??????";
        endcase
    endfunction

    task run_tc;
        input [23:0]  tc_label;
        input integer hr_bpm_in;
        input real    temp_c_in;
        input integer spo2_pct_in;
        input [11:0]  hr_adc_in;
        input [11:0]  temp_adc_in;
        input [11:0]  spo2_adc_in;
        input [47:0]  expected_str;
        integer wait_cnt;
        reg [1:0] hr_c, temp_c, spo2_c;
        begin
            $display("----------------------------------------------------------");
            $display("[%0t ns] [STIM] %s | HR=%0d Temp=%.1fC SpO2=%0d%%  Expected=%s",
                     $time, tc_label, hr_bpm_in, temp_c_in, spo2_pct_in, expected_str);

            hr_raw       = hr_adc_in;
            temp_raw     = temp_adc_in;
            spo2_raw     = spo2_adc_in;
            resp_raw     = 12'h400;
            sample_valid = 1'b1;
            @(posedge clk); #1;
            sample_valid = 1'b0;

            // Wait norm_valid
            wait_cnt = 0;
            while (!u_dut.norm_valid && wait_cnt < 10) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            $display("[%0t ns] [NORM] HR=%0d(%.3f) Temp=%0d(%.3f) SpO2=%0d(%.3f)",
                     $time,
                     u_dut.norm_data[0], q88_to_real(u_dut.norm_data[0]),
                     u_dut.norm_data[1], q88_to_real(u_dut.norm_data[1]),
                     u_dut.norm_data[2], q88_to_real(u_dut.norm_data[2]));

            // Wait output valid
            wait_cnt = 0;
            while (!u_dut.out_valid[0] && wait_cnt < 20) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            @(posedge clk); #1;
            $display("[%0t ns] [OUTL] GREEN=%0d(%.3f) YELLOW=%0d(%.3f) RED=%0d(%.3f)",
                     $time,
                     u_dut.out_scores[0], q88_to_real(u_dut.out_scores[0]),
                     u_dut.out_scores[1], q88_to_real(u_dut.out_scores[1]),
                     u_dut.out_scores[2], q88_to_real(u_dut.out_scores[2]));

            // Wait enc_valid
            wait_cnt = 0;
            while (!u_dut.enc_valid && wait_cnt < 10) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            @(posedge clk); #1;
            @(posedge clk); #1;

            // Read cause byte
            hr_c   = u_dut.cause_byte[5:4];
            temp_c = u_dut.cause_byte[3:2];
            spo2_c = u_dut.cause_byte[1:0];

            $display("[%0t ns] [PENC] PRIORITY=%s  confidence=%0d",
                     $time, pri_str(led_priority), u_dut.confidence);
            $display("              CAUSE: HR=%s  Temp=%s  SpO2=%s",
                     cause_str(hr_c), cause_str(temp_c), cause_str(spo2_c));

            // Wait UART
            wait_cnt = 0;
            while (uart_tx_pin == 1'b1 && wait_cnt < 2000) begin
                @(posedge clk); #1; wait_cnt = wait_cnt + 1;
            end
            // 4 bytes x 10 bits x 868 clocks = 34720 cycles
            repeat(35000) @(posedge clk); #1;

            $display("[%0t ns] [LED ] red=%b yellow=%b green=%b",
                     $time, led_red, led_yellow, led_green);

            if (pri_str(led_priority) == expected_str)
                $display("[%0t ns] [PASS] Expected=%s  Got=%s",
                         $time, expected_str, pri_str(led_priority));
            else
                $display("[%0t ns] [FAIL] Expected=%s  Got=%s",
                         $time, expected_str, pri_str(led_priority));

            repeat(20) @(posedge clk);
        end
    endtask

    // ADC values:
    // hr_raw   = round(hr  / 220 * 4095)
    // temp_raw = round((t  - 34) / 8  * 4095)
    // spo2_raw = round((s  - 50) / 50 * 4095)
    //
    //  80bpm  -> 0x5D1    37.0C -> 0x600    98% -> 0xF5C
    // 110bpm  -> 0x800    38.0C -> 0x800    94% -> 0xEB8
    // 150bpm  -> 0xAE8    39.5C -> 0xB00    82% -> 0xC30
    //  35bpm  -> 0x28C    34.5C -> 0x100    70% -> 0x9C4
    // 220bpm  -> 0xFFF    42.0C -> 0xFFF   100% -> 0xFFF
    initial begin
        rst_n        = 1'b0;
        sample_valid = 1'b0;
        hr_raw       = 12'h000;
        temp_raw     = 12'h000;
        spo2_raw     = 12'h000;
        resp_raw     = 12'h000;

        repeat(10) @(posedge clk); #1;
        rst_n = 1'b1;
        repeat(5)  @(posedge clk); #1;

        $display("==========================================================");
        $display("  triage_top - Phase 5: HR + Temp + SpO2");
        $display("  Network: 3->16->3  +  Cause classification");
        $display("  Label: worst case wins");
        $display("==========================================================");
run_tc("TC1",  80, 37.0, 98, 12'h5D1, 12'h600, 12'hE66, "GREEN "); //march 22 2pm changes
run_tc("TC2", 110, 38.0, 94, 12'h800, 12'h800, 12'hB33, "YELLOW");
run_tc("TC3", 150, 39.5, 82, 12'hAE8, 12'hB00, 12'h19A, "RED   ");
run_tc("TC4", 150, 37.0, 98, 12'hAE8, 12'h600, 12'hE66, "RED   ");
run_tc("TC5",  80, 39.5, 98, 12'h5D1, 12'hB00, 12'hE66, "RED   ");
run_tc("TC6",  80, 37.0, 82, 12'h5D1, 12'h600, 12'h19A, "RED   ");
run_tc("TC7", 110, 37.0, 98, 12'h800, 12'h600, 12'hE66, "GREEN ");
run_tc("TC8",  80, 37.0, 92, 12'h5D1, 12'h600, 12'h999, "YELLOW");
       /* // TC1: all normal -> GREEN
        run_tc("TC1",  80, 37.0, 98, 12'h5D1, 12'h600, 12'hF5C, "GREEN ");

        // TC2: all mild -> YELLOW
        run_tc("TC2", 110, 38.0, 94, 12'h800, 12'h800, 12'hEB8, "YELLOW");

        // TC3: all RED -> RED
        run_tc("TC3", 150, 39.5, 82, 12'hAE8, 12'hB00, 12'hC30, "RED   ");

        // TC4: HR RED only -> RED (cause: HR=RED Temp=normal SpO2=normal)
        run_tc("TC4", 150, 37.0, 98, 12'hAE8, 12'h600, 12'hF5C, "RED   ");

        // TC5: Temp RED only -> RED (cause: HR=normal Temp=RED SpO2=normal)
        run_tc("TC5",  80, 39.5, 98, 12'h5D1, 12'hB00, 12'hF5C, "RED   ");

        // TC6: SpO2 RED only -> RED (cause: HR=normal Temp=normal SpO2=RED)
        run_tc("TC6",  80, 37.0, 82, 12'h5D1, 12'h600, 12'hC30, "RED   ");

        // TC7: HR mild, others normal -> YELLOW
        run_tc("TC7", 110, 37.0, 98, 12'h800, 12'h600, 12'hF5C, "YELLOW");

        // TC8: SpO2 mild, others normal -> YELLOW
        run_tc("TC8",  80, 37.0, 92, 12'h5D1, 12'h600, 12'hEB8, "YELLOW");*/

     /*   $display("==========================================================");
        $display("  All test cases complete.");
        $display("==========================================================");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("*** WATCHDOG: exceeded 200ms ***");
        $finish;
    end

endmodule */
