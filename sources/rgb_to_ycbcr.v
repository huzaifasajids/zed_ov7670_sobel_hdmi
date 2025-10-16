module rgb_to_ycbcr (
    input wire [7:0] r_in,    // 8-bit Red input
    input wire [7:0] g_in,    // 8-bit Green input
    input wire [7:0] b_in,    // 8-bit Blue input
    
    output wire [7:0] y_out,  // 8-bit Y (Luminance) output
    output wire [7:0] cb_out, // 8-bit Cb (Blue-difference chroma) output
    output wire [7:0] cr_out  // 8-bit Cr (Red-difference chroma) output
);

// ITU-R BT.709 coefficients scaled by 1024 for better precision
// Y = 0.2126*R + 0.7152*G + 0.0722*B
wire [17:0] y_r_prod = r_in * 218;   // 0.2126 * 1024 ? 218
wire [18:0] y_g_prod = g_in * 732;   // 0.7152 * 1024 ? 732  
wire [16:0] y_b_prod = b_in * 74;    // 0.0722 * 1024 ? 74

// Cb = -0.1146*R - 0.3854*G + 0.5000*B + 128
wire [17:0] cb_r_prod = r_in * 117;  // 0.1146 * 1024 ? 117 (will be subtracted)
wire [18:0] cb_g_prod = g_in * 395;  // 0.3854 * 1024 ? 395 (will be subtracted)
wire [17:0] cb_b_prod = b_in * 512;  // 0.5000 * 1024 = 512

// Cr = 0.5000*R - 0.4542*G - 0.0458*B + 128
wire [17:0] cr_r_prod = r_in * 512;  // 0.5000 * 1024 = 512
wire [18:0] cr_g_prod = g_in * 465;  // 0.4542 * 1024 ? 465 (will be subtracted)
wire [16:0] cr_b_prod = b_in * 47;   // 0.0458 * 1024 ? 47 (will be subtracted)

// Sum computations
wire [18:0] y_sum = y_r_prod + y_g_prod + y_b_prod;
wire [18:0] cb_sum_pos = cb_b_prod + 19'd131072;  // Add 128*1024 = 131072 for offset
wire [18:0] cb_sum_neg = cb_r_prod + cb_g_prod;
wire [18:0] cr_sum_pos = cr_r_prod + 19'd131072;  // Add 128*1024 = 131072 for offset  
wire [18:0] cr_sum_neg = cr_g_prod + cr_b_prod;

// Final differences (handle signed arithmetic properly)
wire [19:0] cb_diff = {1'b0, cb_sum_pos} - {1'b0, cb_sum_neg};
wire [19:0] cr_diff = {1'b0, cr_sum_pos} - {1'b0, cr_sum_neg};

// Get full range values (0-255)
wire [15:0] y_full = y_sum >> 10;      // Divide by 1024
wire [15:0] cb_full = cb_diff >> 10;   // Divide by 1024  
wire [15:0] cr_full = cr_diff >> 10;   // Divide by 1024

// Convert to limited range: Y [10-235], Cb/Cr [16-240]
// More accurate scaling: use 256 instead of 255 for efficiency
// Y_limited = 10 + (Y_full * 225) / 256
// Cb/Cr_limited = 16 + (Cb/Cr_full * 224) / 256

wire [23:0] y_temp = y_full * 225;    // Scale by 225 (235-10 = 225)
wire [23:0] cb_temp = cb_full * 224;  // Scale by 224 (240-16 = 224)
wire [23:0] cr_temp = cr_full * 224;  // Scale by 224

wire [15:0] y_scaled = (y_temp >> 8) + 16'd10;   // Divide by 256, add offset
wire [15:0] cb_scaled = (cb_temp >> 8) + 16'd16; // Divide by 256, add offset
wire [15:0] cr_scaled = (cr_temp >> 8) + 16'd16; // Divide by 256, add offset

// Final saturation
wire [7:0] y_sat = (y_scaled > 16'd235) ? 8'd235 :   
                   (y_scaled < 16'd10) ? 8'd10 :     
                   y_scaled[7:0];                    

wire [7:0] cb_sat = (cb_scaled > 16'd240) ? 8'd240 : 
                    (cb_scaled < 16'd16) ? 8'd16 :   
                    cb_scaled[7:0];                  

wire [7:0] cr_sat = (cr_scaled > 16'd240) ? 8'd240 :  
                    (cr_scaled < 16'd16) ? 8'd16 :   
                    cr_scaled[7:0];                  

// Output assignments
assign y_out = y_sat;
assign cb_out = cb_sat;
assign cr_out = cr_sat;

endmodule