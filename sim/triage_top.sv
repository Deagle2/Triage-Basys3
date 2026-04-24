// =============================================================================
// Module      : triage_top
// Project     : Edge AI Hospital Emergency Triage
// Phase       : 5 - HR + Temp + SpO2 with cause classification
//
// Pipeline:
//   hr_raw + temp_raw + spo2_raw -> triage_vital_normaliser
//   -> hidden layer (16 neurons, 3 inputs, ReLU+clamp)
//   -> output layer (3 neurons, 16 inputs, NO ReLU)
//   -> priority_encoder + cause_encoder
//   -> uart_tx (4-byte packet) -> LEDs
//
// Network   : 3 inputs -> 16 hidden -> 3 output
// Weights   : triage_3input_colab.ipynb
// Format    : Q8.8 fixed-point (256 = 1.0)
//
// UART Packet:
//   Byte 0: 0xAA (start)
//   Byte 1: {6'b0, priority[1:0]}
//   Byte 2: cause {2'b0, hr_cause[1:0], temp_cause[1:0], spo2_cause[1:0]}
//   Byte 3: confidence[15:8]
//
// Cause encoding: 00=normal 01=YELLOW 10=RED
// =============================================================================
`timescale 1ns / 1ps

module triage_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,

    input  wire [11:0] hr_raw,
    input  wire [11:0] spo2_raw,
    input  wire [11:0] temp_raw,
    input  wire [11:0] resp_raw, //fixes ??

    output wire        uart_tx_pin,
    output wire [1:0]  led_priority,
    output wire        led_red,
    output wire        led_yellow,
    output wire        led_green
);
// AUTO-GENERATED  Architecture: 3->16->3  Val acc: 95.2%
// 3 Inputs: HR (bpm) + Temp (C) + SpO2 (%) 
// Q8.8 fixed-point (256=1.0)
// HR:   x=hr_raw*256/4095   (hr_raw=hr_bpm/220*4095)
// Temp: x=temp_raw*256/4095 (temp_raw=(temp_C-34)/8*4095)
// SpO2: x=spo2_raw*256/4095 (spo2_raw=(spo2_pct-80)/20*4095)

localparam signed [15:0] WH [0:15][0:2] = '{
    '{ 16'shFF8E, 16'sh01B1, 16'sh0096 },   // n0: HR=-0.45 T=+1.69 S=+0.59
    '{ 16'shFF91, 16'sh014F, 16'sh00EA },   // n1: HR=-0.43 T=+1.31 S=+0.91
    '{ 16'sh002F, 16'sh0024, 16'sh005B },   // n2: HR=+0.18 T=+0.14 S=+0.36
    '{ 16'sh0135, 16'shFEC6, 16'sh0297 },   // n3: HR=+1.21 T=-1.23 S=+2.59
    '{ 16'shFEDF, 16'sh00FB, 16'sh0223 },   // n4: HR=-1.13 T=+0.98 S=+2.14
    '{ 16'sh02CB, 16'sh02DA, 16'shFFDE },   // n5: HR=+2.79 T=+2.85 S=-0.13
    '{ 16'shFF8A, 16'sh009F, 16'sh016F },   // n6: HR=-0.46 T=+0.62 S=+1.44
    '{ 16'shFF61, 16'sh00BB, 16'sh01A6 },   // n7: HR=-0.62 T=+0.73 S=+1.65
    '{ 16'sh0000, 16'sh0000, 16'sh0000 },   // n8: HR=-0.00 T=+0.00 S=-0.00
    '{ 16'shFFA5, 16'shFFE5, 16'shFF80 },   // n9: HR=-0.36 T=-0.11 S=-0.50
    '{ 16'shFEB1, 16'sh0300, 16'shFF22 },   // n10: HR=-1.31 T=+3.00 S=-0.87
    '{ 16'sh00EE, 16'sh0300, 16'shFDA0 },   // n11: HR=+0.93 T=+3.00 S=-2.37
    '{ 16'sh0000, 16'sh0000, 16'sh0000 },   // n12: HR=-0.00 T=-0.00 S=-0.00
    '{ 16'sh0000, 16'sh0000, 16'sh0000 },   // n13: HR=-0.00 T=-0.00 S=+0.00
    '{ 16'shFF71, 16'shFFD4, 16'shFF39 },   // n14: HR=-0.56 T=-0.17 S=-0.78
    '{ 16'shFEBD, 16'sh009A, 16'shFE12 }   // n15: HR=-1.26 T=+0.60 S=-1.93
};

localparam signed [15:0] BH [0:15] = '{
    16'shFFC5,   // n0: -0.2290
    16'shFFB5,   // n1: -0.2924
    16'sh00AA,   // n2: +0.6632
    16'shFE51,   // n3: -1.6846
    16'shFF4D,   // n4: -0.6977
    16'shFE16,   // n5: -1.9124
    16'shFFBF,   // n6: -0.2536
    16'shFF98,   // n7: -0.4052
    16'sh0000,   // n8: -0.0000
    16'sh007E,   // n9: +0.4928
    16'shFFC2,   // n10: -0.2431
    16'sh0106,   // n11: +1.0251
    16'sh0000,   // n12: -0.0000
    16'sh0000,   // n13: -0.0000
    16'sh00C5,   // n14: +0.7690
    16'sh0198   // n15: +1.5921
};

localparam signed [15:0] WO [0:2][0:15] = '{
    '{ 16'shFF87, 16'sh0016, 16'shFFAF, 16'sh01A7, 16'sh01DB, 16'shFCEE, 16'sh00E5, 16'sh0123, 16'sh0000, 16'shFFE4, 16'shFF68, 16'shFC5F, 16'sh0000, 16'sh0000, 16'shFFD5, 16'shFFA1 },  // GREEN 
    '{ 16'sh0144, 16'sh00D9, 16'sh002A, 16'shFD38, 16'shFF9B, 16'shFE88, 16'shFFF1, 16'shFFE2, 16'sh0000, 16'shFF83, 16'shFCE0, 16'sh02AB, 16'sh0000, 16'sh0000, 16'shFF3E, 16'shFE28 },  // YELLOW
    '{ 16'shFF03, 16'shFEF5, 16'sh0035, 16'sh011D, 16'shFE4C, 16'sh0483, 16'shFF1D, 16'shFEE2, 16'sh0000, 16'sh0098, 16'sh03B4, 16'sh00D2, 16'sh0000, 16'sh0000, 16'sh00ED, 16'sh023A }  // RED   
};

localparam signed [15:0] BO [0:2] = '{
    16'shFFC2,   // GREEN : -0.2427
    16'shFFBB,   // YELLOW: -0.2683
    16'sh00BE   // RED   : +0.7422
};


    wire signed [15:0] norm_data  [0:7];
    wire               norm_valid;

    // 3-element input vector: [HR, Temp, SpO2]
    wire signed [15:0] input_vec [0:2];
    assign input_vec[0] = norm_data[0];   // HR   normalised
    assign input_vec[1] = norm_data[1];   // Temp normalised
    assign input_vec[2] = norm_data[2];   // SpO2 normalised

    wire signed [15:0] hidden_out  [0:15];
    wire               hidden_valid [0:15];

    wire all_hidden_valid = &{
        hidden_valid[15], hidden_valid[14], hidden_valid[13], hidden_valid[12],
        hidden_valid[11], hidden_valid[10], hidden_valid[ 9], hidden_valid[ 8],
        hidden_valid[ 7], hidden_valid[ 6], hidden_valid[ 5], hidden_valid[ 4],
        hidden_valid[ 3], hidden_valid[ 2], hidden_valid[ 1], hidden_valid[ 0]
    };

    wire signed [15:0] out_scores [0:2];
    wire               out_valid  [0:2];

    reg enc_valid_d1, enc_valid_in; 
    //adding 2 stage pipeline delay as priority encoder was reading 1 cycle too early in triage_top_tb.sv
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enc_valid_d1 <= 1'b0;
        enc_valid_in <= 1'b0;
    end else begin
        enc_valid_d1 <= out_valid[0];
        enc_valid_in <= enc_valid_d1;
    end
end

    wire [1:0]  priority_val;
    wire [15:0] confidence;
    wire        enc_valid;
    wire        alert_red_pulse;
    wire        alert_yellow_pulse;

    // =========================================================================
    // CAUSE CLASSIFICATION
    // Independently classify each vital sign and encode into cause byte
    // cause[5:4] = HR   status (00=normal 01=yellow 10=red)
    // cause[3:2] = Temp status (00=normal 01=yellow 10=red)
    // cause[1:0] = SpO2 status (00=normal 01=yellow 10=red)
    //
    // Thresholds in Q8.8 (256=1.0):
    //   HR:   norm = hr_bpm/220  -> GREEN: 60-100bpm = 0.273-0.455 = 70-116
    //   Temp: norm = (t-34)/8    -> GREEN: 36.1-37.5C = 0.263-0.438 = 67-112
    //   SpO2: norm = (s-50)/50   -> GREEN: >=95% = 0.9 = 230
    // =========================================================================
    reg [1:0] hr_cause;
    reg [1:0] temp_cause;
    reg [1:0] spo2_cause;
    wire [7:0] cause_byte = {2'b00, hr_cause, temp_cause, spo2_cause};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hr_cause   <= 2'b00;
            temp_cause <= 2'b00;
            spo2_cause <= 2'b00;
        end else if (norm_valid) begin
            // HR cause: norm_data[0]
            // GREEN: 70-116 (60-100bpm)  YELLOW: 58-69 or 117-145  RED: else
            if (norm_data[0] >= 16'sd70 && norm_data[0] <= 16'sd116)
                hr_cause <= 2'b00;  // GREEN
            else if ((norm_data[0] >= 16'sd58 && norm_data[0] < 16'sd70) ||
                     (norm_data[0] > 16'sd116 && norm_data[0] <= 16'sd145))
                hr_cause <= 2'b01;  // YELLOW
            else
                hr_cause <= 2'b10;  // RED

            // Temp cause: norm_data[1]
            // GREEN: 67-112 (36.1-37.5C)  YELLOW: 51-66 or 113-147  RED: else
            if (norm_data[1] >= 16'sd67 && norm_data[1] <= 16'sd112)
                temp_cause <= 2'b00;  // GREEN
            else if ((norm_data[1] >= 16'sd51 && norm_data[1] < 16'sd67) ||
                     (norm_data[1] > 16'sd112 && norm_data[1] <= 16'sd147))
                temp_cause <= 2'b01;  // YELLOW
            else
                temp_cause <= 2'b10;  // RED

            // SpO2 cause: norm_data[2]
            // GREEN: >=230 (>=95%)  YELLOW: 205-229 (90-94%)  RED: <205
            if (norm_data[2] >= 16'sd192)
    spo2_cause <= 2'b00;   // GREEN  (SpO2>=95%)
else if (norm_data[2] >= 16'sd128)
    spo2_cause <= 2'b01;   // YELLOW (SpO2 90-94%)
else
    spo2_cause <= 2'b10;   // RED    (SpO2<90%)
        end
    end
 
    // STAGE 1: Normalise HR, Temp, SpO2
    triage_vital_normaliser #(
        .ADC_W  (12),
        .DATA_W (16)
    ) u_norm (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .hr_raw       (hr_raw),
        .spo2_raw     (spo2_raw),
        .temp_raw     (temp_raw),
        .resp_raw     (resp_raw), //fixes
        .norm_out     (norm_data),
        .valid_out    (norm_valid)
    );
    
    // STAGE 2: Hidden layer - 16 neurons, 3 inputs each
    genvar n;
    generate
        for (n = 0; n < 16; n = n + 1) begin : GEN_HIDDEN
            perceptron_layer #(
                .N_INPUTS (3),
                .DATA_W   (16),
                .USE_RELU (1)
            ) u_hidden (
                .clk      (clk),
                .rst_n    (rst_n),
                .valid_in (norm_valid),
                .data_in  (input_vec),
                .weights  (WH[n]),
                .bias     (BH[n]),
                .data_out (hidden_out[n]),
                .valid_out(hidden_valid[n])
            );
        end
    endgenerate
 
    // STAGE 3: Output layer - 3 neurons, 16 inputs each
    generate
        for (n = 0; n < 3; n = n + 1) begin : GEN_OUTPUT
            perceptron_layer #(
                .N_INPUTS (16),
                .DATA_W   (16),
                .USE_RELU (0)
            ) u_out (
                .clk      (clk),
                .rst_n    (rst_n),
                .valid_in (all_hidden_valid),
                .data_in  (hidden_out),
                .weights  (WO[n]),
                .bias     (BO[n]),
                .data_out (out_scores[n]),
                .valid_out(out_valid[n])
            );
        end
    endgenerate

    // STAGE 4: Priority encoder
    priority_encoder #(
        .DATA_W (16)
    ) u_enc (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_in    (enc_valid_in),
        .score_green (out_scores[0]),
        .score_yellow(out_scores[1]),
        .score_red   (out_scores[2]),
        .priority_out(priority_val),
        .confidence  (confidence),
        .alert_red   (alert_red_pulse),
        .alert_yellow(alert_yellow_pulse),
        .valid_out   (enc_valid)
    );

    
    // STAGE 5: UART - 4-byte packet with priority + cause + confidence     
    // Check if the deterministic logic says the patient is fine
    wire logic_says_all_normal = (hr_cause == 2'b00 && temp_cause == 2'b00 && spo2_cause == 2'b00);

    // Create the corrected priority signal: If safe, force GREEN.
    wire [1:0] final_priority = logic_says_all_normal ? 2'b00 : priority_val;

    // =========================================================================
    // STAGE 5: UART - Update to use final_priority
    // =========================================================================
    uart_tx #(
        .CLK_FREQ  (100_000_000),
        .BAUD_RATE (115_200)
    ) u_uart (
        .clk           (clk),
        .rst_n         (rst_n),
        .priority_in   (final_priority), // <--- FIXED: Use final_priority here
        .cause_in      (cause_byte),
        .confidence_in (confidence[15:8]),
        .send          (enc_valid),
        .tx            (uart_tx_pin),
        .busy          ()
    );
 
    // LEDs - Update to use final_priority
    assign led_priority = final_priority;             // <--- FIXED
    assign led_red      = (final_priority == 2'b10);  // <--- FIXED
    assign led_yellow   = (final_priority == 2'b01);  // <--- FIXED
    assign led_green    = (final_priority == 2'b00);  // <--- FIXED

endmodule
