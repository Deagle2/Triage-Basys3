`timescale 1ns / 1ps
/*
// Module      : perceptron_layer
// Project     : Edge AI Hospital Emergency Triage
//
// Computes: output = activation( dot(inputs, weights) + bias )
//
// Parameters:
//   N_INPUTS  - number of inputs
//   DATA_W    - data width (Q8.8, so 16 bits)
//   USE_RELU  - 1 = ReLU + clamp to 255 (hidden layers)
//               0 = pass raw signed value through (output layer)
//
// Q8.8 arithmetic:
//   Two Q8.8 values multiplied = Q16.16 (32-bit result)
//   Sum of N products into wide accumulator, shift right 8 = Q8.8 output
//
// USE_RELU=1 (hidden layer):
//   negative  -> 0        (ReLU)
//   0 to 255  -> as-is    (normal)
//   above 255 -> 255      (clamp, matches torch.clamp(0, 1.0) in Colab)
//
// USE_RELU=0 (output layer):
//   passes signed logit through with saturation at min/max Q8.8
//   allows negative scores so argmax works correctly across all 3 classes
//
// Latency: 2 clock cycles
*/
module perceptron_layer #(
    parameter N_INPUTS = 1,
    parameter DATA_W   = 16,
    parameter USE_RELU = 1
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     valid_in,

    input  wire signed [DATA_W-1:0] data_in [0:N_INPUTS-1],
    input  wire signed [DATA_W-1:0] weights [0:N_INPUTS-1],
    input  wire signed [DATA_W-1:0] bias,

    output reg  signed [DATA_W-1:0] data_out,
    output reg                      valid_out
);

    // Accumulator wide enough to hold sum of all Q16.16 products
    localparam ACC_W = DATA_W * 2 + $clog2(N_INPUTS + 1); 
// Stage 1a: Combinational dot product + bias
 
    integer i;
    reg signed [ACC_W-1:0] acc_comb;

    always @(*) begin
       acc_comb = {{(ACC_W-DATA_W){bias[DATA_W-1]}}, bias} <<< 8;   // new Q16.16sign-extend bias
        for (i = 0; i < N_INPUTS; i = i + 1)
            acc_comb = acc_comb + (data_in[i] * weights[i]);
    end 
    // Stage 1b: Register accumulated result
    reg signed [ACC_W-1:0] acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= 0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in)
                acc <= acc_comb;
        end
    end
// Stage 2: Shift Q16.16 -> Q8.8, apply activation

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 0;
        end else if (valid_out) begin

            if (USE_RELU) begin
                /*
                 Hidden layer: ReLU + clamp to 255
                 Matches Colab: torch.relu(x) then torch.clamp(x, 0.0, 1.0)
                 In Q8.8: 1.0 = 256, so clamp upper limit = 255
                */
                if (acc[ACC_W-1]) begin
                    // Negative -> ReLU clips to 0
                    data_out <= 16'sd0;
                end else if (acc[DATA_W+7:8] > 16'sd255) begin
                    // Above 1.0 -> clamp to 255 (= 0.996, approx 1.0 in Q8.8)
                    data_out <= 16'sd255;
                end else begin
                    // Normal range: take Q8.8 slice
                    data_out <= acc[DATA_W+7:8];
                end

            end else begin
                // -------------------------------------------------------------
                // Output layer: no ReLU, pass signed logit through
                // Saturate at Q8.8 min/max to prevent wrap-around
                // Negative logits are preserved for correct argmax
                // -------------------------------------------------------------
                if (acc[ACC_W-1] && !(&acc[ACC_W-1:DATA_W+8])) begin
                    // Negative underflow -> saturate to most negative Q8.8
                    data_out <= {1'b1, {(DATA_W-1){1'b0}}};
                end else if (!acc[ACC_W-1] && (|acc[ACC_W-1:DATA_W+8])) begin
                    // Positive overflow -> saturate to most positive Q8.8
                    data_out <= {1'b0, {(DATA_W-1){1'b1}}};
                end else begin
                    // Normal: take Q8.8 slice
                    data_out <= acc[DATA_W+7:8];
                end

            end
        end
    end

endmodule