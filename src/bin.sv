`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 13:03:53
// Design Name: 
// Module Name: bin
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module bin2bcd_12bit(
    input  logic [11:0] bin,
    output logic [3:0]  bcd3,  
    output logic [3:0]  bcd2, 
    output logic [3:0]  bcd1, 
    output logic [3:0]  bcd0  
);
    integer i;
    logic [27:0] shift_reg; // 12 bits bin + 16 bits BCD

    always_comb begin
        shift_reg = {16'd0, bin};
        
        for (i = 0; i < 12; i = i + 1) begin
           
            if (shift_reg[15:12] > 4) shift_reg[15:12] = shift_reg[15:12] + 3;
            if (shift_reg[19:16] > 4) shift_reg[19:16] = shift_reg[19:16] + 3;
            if (shift_reg[23:20] > 4) shift_reg[23:20] = shift_reg[23:20] + 3;
            if (shift_reg[27:24] > 4) shift_reg[27:24] = shift_reg[27:24] + 3;
            
             
            shift_reg = shift_reg << 1;
        end
        
        {bcd3, bcd2, bcd1, bcd0} = shift_reg[27:12];
    end
endmodule