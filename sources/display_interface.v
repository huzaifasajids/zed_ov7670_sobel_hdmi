module display_interface 
(
    input  wire        i_p_clk,     // pixel clock (25MHz)
    input  wire        i_rstn,
    input  wire        i_sw_mode,
    // frame buffer interface
    output reg  [18:0] o_raddr,
    input  wire [11:0] i_rdata,
    // HDMI Interface
    input  wire        i_hdmi_int,
    input  wire        i_hdmi_spdif_out,
    output wire        o_hdmi_spdif,
    output wire        o_hdmi_vsync,
    output wire        o_hdmi_hsync,
    output wire        o_hdmi_de,
    output wire        o_hdmi_clk,
    output wire [15:0] o_hdmi_data,
    output wire        o_hdmi_iic_scl,
    inout  wire        io_hdmi_iic_sda
);

// Configure HDMI (ADV7511)
wire config_ok;
hdmi_config hdmi_config_i(
    .i_clk_25MHz    (i_p_clk        ),
    .i_rst          (~i_rstn        ),
    .o_config_ok    (config_ok      ),
    .o_iic_scl      (o_hdmi_iic_scl ),
    .io_iic_sda     (io_hdmi_iic_sda)
);
assign o_hdmi_spdif = 1'b0;
assign o_hdmi_clk = i_p_clk;

// Instantiate Video Timing Controller
wire [9:0]  counterX, counterY;
vtc vtc_i (
    .i_clk         (i_p_clk         ), // pixel clock
    .i_rstn        (i_rstn          ), 
    // timing signals
    .o_vsync       (o_hdmi_vsync    ),
    .o_hsync       (o_hdmi_hsync    ),
    .o_active      (o_hdmi_de       ),
    // counter passthrough
    .o_counterX    (counterX        ),
    .o_counterY    (counterY        )
);

// Data Read Logic (FSM)
reg  [18:0] nxt_raddr;
localparam  STATE_INITIAL = 0,
            STATE_DELAY   = 1,
            STATE_IDLE    = 3,
            STATE_ACTIVE  = 2;
            
reg  [1:0]  STATE = STATE_INITIAL;
reg  [1:0]  NEXT_STATE;

// next state combinational logic
always@* begin
    nxt_raddr  = o_raddr;
    NEXT_STATE = STATE;
    case(STATE)
        // wait 2 frames for camera configuration on reset/startup
        STATE_INITIAL: begin
            NEXT_STATE = ((counterX == 640) && (counterY == 480)) ? STATE_DELAY : STATE_INITIAL;
        end
        STATE_DELAY: begin
            NEXT_STATE = ((counterX == 640) && (counterY == 480)) ? STATE_ACTIVE : STATE_DELAY;
        end
        STATE_IDLE: begin
            if((counterX == 799) && ((counterY == 524) || (counterY < 480))) begin
                nxt_raddr  = o_raddr + 1;
                NEXT_STATE = STATE_ACTIVE;
            end
            else if(counterY > 479) begin
                nxt_raddr = 0;
            end
        end
        // normal operation: begin reading from frame buffer at start of frame
        STATE_ACTIVE: begin
            if(o_hdmi_de && (counterX < 639)) begin
                nxt_raddr = (o_raddr == 307199) ? 0 : (o_raddr + 1);
            end
            else begin
                NEXT_STATE = STATE_IDLE;
            end
        end
    endcase
end

// registered state logic
always@(posedge i_p_clk) begin
    if(!i_rstn) begin
        o_raddr <= 0;
        STATE <= STATE_DELAY;
    end
    else begin
        o_raddr <= nxt_raddr;
        STATE   <= NEXT_STATE;
    end
end

// Assign rgb based on mode; rgb or greyscale
reg  [7:0]  red, green, blue;
always@* begin
    if(i_sw_mode) begin
        red   = i_rdata;
        green = i_rdata;
        blue  = i_rdata;
    end
    else begin
        red   = {i_rdata[3:0],  {4'hF} };
        green = {i_rdata[7:4],  {4'hF} }; 
        blue  = {i_rdata[11:8], {4'hF} }; 
    end
end

// test pattern using RGB values
//localparam BAR_WIDTH = 80;  
//wire [2:0] bar_index = counterX / BAR_WIDTH;

//always @* begin
//    case (bar_index)
//        3'd0: {red, green, blue} = {8'hFF, 8'hFF, 8'hFF}; // White
//        3'd1: {red, green, blue} = {8'h00, 8'hFF, 8'hFF}; // Cyan (G+B)
//        3'd2: {red, green, blue} = {8'hFF, 8'hFF, 8'h00}; // Yellow (R+G)
//        3'd3: {red, green, blue} = {8'hFF, 8'h00, 8'h00}; // Red
//        3'd4: {red, green, blue} = {8'h00, 8'hFF, 8'h00}; // Green
//        3'd5: {red, green, blue} = {8'h00, 8'h00, 8'hFF}; // Blue
//        3'd6: {red, green, blue} = {8'h00, 8'h00, 8'h00}; // Black
//        3'd7: {red, green, blue} = {8'hFF, 8'h00, 8'hFF}; // Magenta (R+B)
//    endcase
//end

// Convert RGB to YCbCr
wire [7:0] data_y;
wire [7:0] data_cb;
wire [7:0] data_cr;
rgb_to_ycbcr rgb_to_ycbcr_i(
    .r_in(red),         // 8-bit Red input
    .g_in(green),       // 8-bit Green input
    .b_in(blue),        // 8-bit Blue input
    .y_out(data_y),     // 8-bit Y (Luminance) output
    .cb_out(data_cb),   // 8-bit Cb (Blue-difference chroma) output
    .cr_out(data_cr)    // 8-bit Cr (Red-difference chroma) output
);
    
assign o_hdmi_data = counterX[0] ? {data_cr, data_y} : {data_cb, data_y};

endmodule