`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.03.2026 15:19:35
// Design Name: 
// Module Name: basys3_triage_top
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


module basys3_triage_top(
    input  wire       clk,            // 100MHz Pin W5
    input  wire       btnC,           // Center Button: Next Patient (0-9)
    input  wire       btnR,           // Right Button: Reset to Patient 0
    input  wire       btnU, // Show SpO2 (Upper button)
    input  wire       btnL, // Show Temp (Left button)
    input  wire       btnD, // Show HR   (Down button)
    output wire [3:0] an,               // 7-Segment Anodes
    output wire [6:0] seg,            // 7-Segment Cathodes
    output wire       led_red,        // LD0: Priority RED
    output wire       led_yellow,     // LD1: Priority YELLOW
    output wire       led_green,      // LD2: Priority GREEN
    output wire       uart_tx_pin    
    
);

   
    reg [3:0] patient_idx;
    reg btn_prev;
    wire btn_pulse = btnC && !btn_prev; // Trigger only on the initial press

    always @(posedge clk) begin
        btn_prev <= btnC;
        if (btnR) begin
            patient_idx <= 4'd0;
        end else if (btn_pulse) begin
            if (patient_idx < 9) patient_idx <= patient_idx + 1;
            else patient_idx <= 0; // Loop back to 0
        end
    end

   
    // LUT/ROM (TC1 to TC10)
    reg [11:0] hr_rom, temp_rom, spo2_rom;
    always @(*) begin
        case(patient_idx)
            // values from triage_top_tb.sv
            4'd0: begin hr_rom=12'd1339; temp_rom=12'd1331; spo2_rom=12'd3890; end // TC1: Green
            4'd1: begin hr_rom=12'd1395; temp_rom=12'd1280; spo2_rom=12'd4095; end // TC2: Green
            4'd2: begin hr_rom=12'd2048; temp_rom=12'd1536; spo2_rom=12'd3686; end // TC3: Green
            4'd3: begin hr_rom=12'd1489; temp_rom=12'd2048; spo2_rom=12'd3686; end // TC4: Yellow
            4'd4: begin hr_rom=12'd1489; temp_rom=12'd1536; spo2_rom=12'd2457; end // TC5: Yellow
            4'd5: begin hr_rom=12'd2048; temp_rom=12'd2048; spo2_rom=12'd2867; end // TC6: Yellow
            4'd6: begin hr_rom=12'd2792; temp_rom=12'd1536; spo2_rom=12'd3686; end // TC7: Red
            4'd7: begin hr_rom=12'd1489; temp_rom=12'd2815; spo2_rom=12'd3686; end // TC8: Red
            4'd8: begin hr_rom=12'd1489; temp_rom=12'd1536; spo2_rom=12'd410;  end // TC9: Red
            4'd9: begin hr_rom=12'd2792; temp_rom=12'd2815; spo2_rom=12'd410;  end // TC10: Red
            default: begin hr_rom=12'd1339; temp_rom=12'd1331; spo2_rom=12'd3890; end
        endcase
    end

   
    triage_top core (
        .clk(clk),
        .rst_n(!btnR),
        .sample_valid(1'b1),
        .hr_raw(hr_rom),
        .spo2_raw(spo2_rom),
        .temp_raw(temp_rom),
        .resp_raw(12'd0),
        .uart_tx_pin(uart_tx_pin),
        .led_red(led_red),        // Maps to LD0
        .led_yellow(led_yellow),  // Maps to LD1
        .led_green(led_green)     // Maps to LD2
    );

    // BCD Conversion 
    wire [3:0] bcd_hr3, bcd_hr2, bcd_hr1, bcd_hr0;
    wire [3:0] bcd_temp3, bcd_temp2, bcd_temp1, bcd_temp0;
    wire [3:0] bcd_spo23, bcd_spo22, bcd_spo21, bcd_spo20;

   
    bin2bcd_12bit bcd_hr   (.bin(hr_rom),   .bcd3(bcd_hr3),   .bcd2(bcd_hr2),   .bcd1(bcd_hr1),   .bcd0(bcd_hr0));
    bin2bcd_12bit bcd_temp (.bin(temp_rom), .bcd3(bcd_temp3), .bcd2(bcd_temp2), .bcd1(bcd_temp1), .bcd0(bcd_temp0));
    bin2bcd_12bit bcd_spo2 (.bin(spo2_rom), .bcd3(bcd_spo23), .bcd2(bcd_spo22), .bcd1(bcd_spo21), .bcd0(bcd_spo20));

    reg [15:0] display_value;
    //Display Vitals : Shows 1339 [12 bit adc values]
    always @(*) begin
        if (btnD)      display_value = {bcd_hr3,   bcd_hr2,   bcd_hr1,   bcd_hr0};   
        else if (btnL) display_value = {bcd_temp3, bcd_temp2, bcd_temp1, bcd_temp0};  
        else if (btnU) display_value = {bcd_spo23, bcd_spo22, bcd_spo21, bcd_spo20};  
        else           display_value = {4'hF, 4'hF, 4'hF, patient_idx}; // Default: Blank Blank Blank ID
    end

   // Seven Seg 
    // We send display_value to show either vitals or the patient index.
    Seven_segment display_unit (
            .clock_100Mhz(clk),
            .reset(btnR),
            .switch(display_value), // DISPLAY VITALS
            .Anode_Activate(an),
            .LED_out(seg)
        );

endmodule