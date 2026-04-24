`timescale 1ns / 1ps

module Seven_segment(
    input  logic        clock_100Mhz,
    input  logic        reset,
    input  logic [15:0] switch,         // We use the last 4 bits for patient_idx
    output logic [3:0]  Anode_Activate, // Which digit is ON
    output logic [6:0]  LED_out         // Cathode patterns
);

    logic [1:0] led_activating_counter; 
    logic [19:0] refresh_counter; 
    logic [3:0]  display_digit; //  

    // refresh_counter[19:18] creates a ~1ms delay for multiplexing
    always_ff @(posedge clock_100Mhz or posedge reset) begin 
        if(reset)
            refresh_counter <= 0;
        else
            refresh_counter <= refresh_counter + 1;
    end
    
    assign led_activating_counter = refresh_counter[19:18];

 
    // 1. Anode Control 
 
    always_comb begin
        case(led_activating_counter)
            2'b00: begin
                Anode_Activate = 4'b0111;     // Digit 1 MSB
                display_digit = switch[15:12]; 
            end
            2'b01: begin
                Anode_Activate = 4'b1011;     // Digit 2 
                display_digit = switch[11:8];  // Show Vitals Hex Digit 3
            end
            2'b10: begin
                Anode_Activate = 4'b1101;     // Digit 3  
                display_digit = switch[7:4];   // Show Vitals Hex Digit 2
            end
            2'b11: begin
                Anode_Activate = 4'b1110;     // Digit 4 LSB
                display_digit = switch[3:0];   // Show Vitals Hex Digit 1 / Patient ID
            end
        endcase
    end

     
    // 2. Cathode Decoder (Active-Low / Common Anode)
  
   always_comb begin
            case(display_digit)
                4'h0:    LED_out = 7'b1000000; // "0"
                4'h1:    LED_out = 7'b1111001; // "1"
                4'h2:    LED_out = 7'b0100100; // "2"
                4'h3:    LED_out = 7'b0110000; // "3"
                4'h4:    LED_out = 7'b0011001; // "4"
                4'h5:    LED_out = 7'b0010010; // "5"
                4'h6:    LED_out = 7'b0000010; // "6"
                4'h7:    LED_out = 7'b1111000; // "7"
                4'h8:    LED_out = 7'b0000000; // "8"
                4'h9:    LED_out = 7'b0010000; // "9"
                4'hA:    LED_out = 7'b0001000; // "A" (HR Label)
                4'hB:    LED_out = 7'b0000011; // "b" (Temp Label)
                4'hC:    LED_out = 7'b1000110; // "C" (SpO2 Label)
                4'hF:    LED_out = 7'b1111111; // Blank
                default: LED_out = 7'b1111111; // All OFF
            endcase
        end

endmodule