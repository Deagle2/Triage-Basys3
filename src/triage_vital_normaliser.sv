//////////////////////////////////////////////////////////////////////////////////
// Module      : triage_vital_normaliser
// Project     : Edge AI Hospital Emergency Triage
// Phase       : 5 - HR + Temp + SpO2
//
// Normalisation (Cell 4)
//   HR:   norm_out[0] = hr_raw   * 256 / 4095
//         hr_raw   = hr_bpm / 220 * 4095
//
//   Temp: norm_out[1] = temp_raw * 256 / 4095
//         temp_raw = (temp_C - 34.0) / 8.0 * 4095
//
//   SpO2: norm_out[2] = spo2_raw * 256 / 4095
//         spo2_raw = (spo2_pct - 80.0) / 20.0 * 4095
//         Maps: 80%->0.0  90%->0.5  100%->1.0
//
//   norm_out[3..7] = 0 reserved for future phases
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
module triage_vital_normaliser #(
    parameter ADC_W  = 12,// 0-4095
    parameter DATA_W = 16)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    sample_valid,

    input  wire [ADC_W-1:0]        hr_raw,
    input  wire [ADC_W-1:0]        spo2_raw,
    input  wire [ADC_W-1:0]        temp_raw,
    input  wire [ADC_W-1:0]        resp_raw,

    output reg signed [DATA_W-1:0] norm_out [0:7],
    output reg                     valid_out
);

    reg [31:0] hr_scaled;
    reg [31:0] temp_scaled;
    reg [31:0] spo2_scaled;
    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            for (j = 0; j < 8; j = j + 1)
                norm_out[j] <= 16'sd0;

        end else if (sample_valid) begin

            // HR: x = hr_raw * 256 / 4095
            hr_scaled   = (hr_raw   * 32'd256) / 32'd4095;
            norm_out[0] <= hr_scaled[DATA_W-1:0];

            // Temp: x = temp_raw * 256 / 4095
            temp_scaled = (temp_raw * 32'd256) / 32'd4095;
            norm_out[1] <= temp_scaled[DATA_W-1:0];

            // SpO2: x = spo2_raw * 256 / 4095
            spo2_scaled = (spo2_raw * 32'd256) / 32'd4095;
            norm_out[2] <= spo2_scaled[DATA_W-1:0];

            // Reserved
            norm_out[3] <= 16'sd0;
            norm_out[4] <= 16'sd0;
            norm_out[5] <= 16'sd0;
            norm_out[6] <= 16'sd0;
            norm_out[7] <= 16'sd0;

            valid_out <= 1'b1;

        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
