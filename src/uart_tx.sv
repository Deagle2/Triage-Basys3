`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module      : uart_tx
// Project     : Edge AI Hospital Emergency Triage
// Description : 8N1 UART transmitter. Sends a 4-byte alert packet.
//
// Packet format: Sending 4 bytes
//   Byte 0 : 0xAA                    start marker
//   Byte 1 : {6'b0, priority[1:0]}   00=GREEN 01=YELLOW 10=RED
//   Byte 2 : cause byte
//             bits [5:4] = HR cause   (00=normal 01=yellow 10=red)
//             bits [3:2] = Temp cause (00=normal 01=yellow 10=red)
//             bits [1:0] = SpO2 cause (00=normal 01=yellow 10=red)
//   Byte 3 : confidence[7:0]
//
// Parameters:
//   CLK_FREQ  : system clock in Hz (default 100 MHz)
//   BAUD_RATE : baud rate (default 115200)
//////////////////////////////////////////////////////////////////////////////////
module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [1:0] priority_in,
    input  wire [7:0] cause_in,        // cause byte (HR/Temp/SpO2 status)
    input  wire [7:0] confidence_in,
    input  wire       send,

    output reg        tx,
    output reg        busy
);

    localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE;

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] baud_cnt;
    reg [2:0]  bit_idx;
    reg [2:0]  byte_idx;   // 0-3 for 4 bytes
    reg [7:0]  shift_reg;
    reg [7:0]  packet [0:3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx       <= 1'b1;
            busy     <= 1'b0;
            baud_cnt <= 0;
            bit_idx  <= 0;
            byte_idx <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    if (send) begin
                        packet[0] <= 8'hAA;
                        packet[1] <= {6'b0, priority_in};
                        packet[2] <= cause_in;
                        packet[3] <= confidence_in;
                        byte_idx  <= 0;
                        busy      <= 1'b1;
                        baud_cnt  <= 0;
                        state     <= START;
                    end
                end
                START: begin
                    tx <= 1'b0;
                    if (baud_cnt == BAUD_DIV - 1) begin
                        baud_cnt  <= 0;
                        shift_reg <= packet[byte_idx];
                        bit_idx   <= 0;
                        state     <= DATA;
                    end else baud_cnt <= baud_cnt + 1;
                end
                DATA: begin
                    tx <= shift_reg[0];
                    if (baud_cnt == BAUD_DIV - 1) begin
                        baud_cnt  <= 0;
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 3'd7) state <= STOP;
                        else bit_idx <= bit_idx + 1;
                    end else baud_cnt <= baud_cnt + 1;
                end
                STOP: begin
                    tx <= 1'b1;
                    if (baud_cnt == BAUD_DIV - 1) begin
                        baud_cnt <= 0;
                        if (byte_idx == 3'd3) state <= IDLE;
                        else begin
                            byte_idx <= byte_idx + 1;
                            state    <= START;
                        end
                    end else baud_cnt <= baud_cnt + 1;
                end
            endcase
        end
    end

endmodule
