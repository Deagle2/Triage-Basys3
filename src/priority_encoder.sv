`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module      : priority_encoder
// Project     : Edge AI Hospital Emergency Triage
// Description : Argmax over 3 signed output logits -> 2-bit triage priority.
//               Uses explicit $signed() casts for correct signed comparison.
//
// Priority codes:
//   2'b00 -> GREEN  (routine)
//   2'b01 -> YELLOW (urgent)
//   2'b10 -> RED    (critical)
//
// 1 clock cycle delay
//////////////////////////////////////////////////////////////////////////////////
module priority_encoder #(
    parameter DATA_W = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     valid_in,

    input  wire signed [DATA_W-1:0] score_green,
    input  wire signed [DATA_W-1:0] score_yellow,
    input  wire signed [DATA_W-1:0] score_red,

    output reg  [1:0]               priority_out,
    output reg  [DATA_W-1:0]        confidence,
    output reg                      alert_red,
    output reg                      alert_yellow,
    output reg                      valid_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priority_out <= 2'b00;
            confidence   <= 0;
            alert_red    <= 1'b0;
            alert_yellow <= 1'b0;
            valid_out    <= 1'b0;
        end else begin
            alert_red    <= 1'b0;
            alert_yellow <= 1'b0;
            valid_out    <= valid_in; //Pipeline fixes
            
// Priority Logic: Red > Yellow > Green.
// If scores are equal, Red is prioritised.
            if (valid_in) begin
    if ($signed(score_red) >= $signed(score_yellow) &&
        $signed(score_red) >= $signed(score_green)) begin
        priority_out <= 2'b10;
        alert_red    <= 1'b1;
        // Confidence = Max_Score - Second_Max_Score.
        confidence   <= ($signed(score_yellow) >= $signed(score_green)) ?
                        $signed(score_red) - $signed(score_yellow) :
                        $signed(score_red) - $signed(score_green);

    end else if ($signed(score_yellow) >= $signed(score_green)) begin
        priority_out <= 2'b01;
        alert_yellow <= 1'b1;
        confidence   <= ($signed(score_red) >= $signed(score_green)) ?
                        $signed(score_yellow) - $signed(score_red) :
                        $signed(score_yellow) - $signed(score_green);

    end else begin
        priority_out <= 2'b00;
        confidence   <= ($signed(score_red) >= $signed(score_yellow)) ?
                        $signed(score_green) - $signed(score_red) :
                        $signed(score_green) - $signed(score_yellow);
    end
end
        end
    end

endmodule