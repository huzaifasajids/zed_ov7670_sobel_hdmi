`default_nettype none

module sys_top 
(
    input  wire        i_sysclk,    // 100 MHz board clock

    // camera interface
    output wire        o_cam_xclk,  // 24MHz clock to camera from DCM
    output wire        o_cam_rstn,  // camera active low reset
    output wire        o_cam_pwdn,  // camera active high power down 
    input  wire        i_cam_pclk,  // camera generated pixel clock
    input  wire        i_cam_vsync, // camera vsync
    input  wire        i_cam_href,  // camera href
    input  wire [7:0]  i_cam_data,  // camera 8-bit data in
    inout  wire        io_cam_scl,  // bidirectional SCL
    inout  wire        io_cam_sda,  // bidirectional SDA
    
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
    inout  wire        io_hdmi_iic_sda,

    // status
    output wire       led_mode,
    output wire       led_gaussian,
    output wire       led_sobel,
    output wire       led_threshold
);

// =============================================================
//              Parameters, Registers, and Wires
// =============================================================
// DCM
    wire        clk_25MHz;
    wire        clk_100MHz;

// User Controls
    wire sw_gaussian;
    wire sw_sobel;
    wire sw_freeze;
    wire sw_mode;
    wire [25:0] sobel_threshold;
    wire btn_rstn;
    
// System Control
    wire        cfg_start;
    wire        gaussian_enable;
    wire        sobel_enable;
    wire        pipe_flush;

// Camera Block
    wire        i_cam_scl, i_cam_sda;
    wire        o_cam_scl, o_cam_sda;
    wire        sof;
    wire        cam_obuf_rd;
    wire [11:0] cam_obuf_rdata;
    wire        cam_obuf_almostempty;
    wire        cfg_done;

// Greyscale Block
    wire        pp_obuf_rd;
    wire [11:0] pp_obuf_rdata;
    wire        pp_obuf_almostempty;

// Gaussian Block
    wire        gssn_obuf_rd;
    wire [11:0] gssn_obuf_rdata;
    wire        gssn_obuf_almostempty;

// Sobel Block
    wire        sobel_obuf_rd;
    wire [11:0] sobel_obuf_rdata;
    wire        sobel_obuf_almostempty;

// Display Interface
    wire [18:0] framebuf_raddr;
    wire [11:0] framebuf_rdata;

// =============================================================
//               Async Reset Synchronizers
// =============================================================

    // 125 MHz
    reg sync_rstn_PS, q_rstn_PS;
    always@(posedge clk_100MHz or negedge btn_rstn) begin
        if(!btn_rstn) {sync_rstn_PS, q_rstn_PS} <= 2'b0;
        else          {sync_rstn_PS, q_rstn_PS} <= {q_rstn_PS, 1'b1};
    end

    // 25 MHz
    reg sync_rstn_25, q_rstn_25;
    always@(posedge clk_25MHz or negedge btn_rstn) begin
        if(!btn_rstn) {sync_rstn_25, q_rstn_25} <= 2'b0;
        else          {sync_rstn_25, q_rstn_25} <= {q_rstn_25, 1'b1};
    end

// =============================================================
//                    Submodule Instantiation:
// =============================================================
    //---------------------------------------------------
    //                 Clocking Wizard:
    //---------------------------------------------------
    clk_wiz_0 
    dcm_i (
        .clk_in1    (i_sysclk      ), // 100MHz board clock
        .reset      (1'b0          ),
        .clk_24M    (o_cam_xclk    ), // camera reference clock output
        .clk_25M    (clk_25MHz     ), // display pixel clock
        .clk_100M   (clk_100MHz    )  // display TMDS clock
    );
    
    //---------------------------------------------------
    //                 User Controls:
    //---------------------------------------------------
    vio_0 vio_i (
        .clk              (clk_100MHz             ),      // input wire clk
        .probe_out0       (sw_gaussian            ),      // output wire [0 : 0] probe_out0
        .probe_out1       (sw_sobel               ),      // output wire [0 : 0] probe_out1
        .probe_out2       (sw_freeze              ),      // output wire [0 : 0] probe_out2
        .probe_out3       (sw_mode                ),      // output wire [0 : 0] probe_out3
        .probe_out4       (sobel_threshold[6:0]   ),      // output wire [6 : 0] probe_out4
        .probe_out5       (btn_rstn               )       // output wire [0 : 0] probe_out5
    );
    assign led_mode      = sw_mode;
    assign led_gaussian  = gaussian_enable;
    assign led_sobel     = sobel_enable;
    assign led_threshold = sobel_threshold > 100;
    
    //---------------------------------------------------
    //                 System Control:
    //---------------------------------------------------
    sys_control 
    ctrl_i (
        .i_sysclk          (clk_100MHz      ), // 125MHz clock
        .i_rstn            (sync_rstn_PS    ), // active-low sync reset
        .i_sof             (sof             ),
        .i_sw_mode         (sw_mode         ),
        .i_sw_gaussian     (sw_gaussian     ),
        .i_sw_sobel        (sw_sobel        ),
        .i_sw_freeze       (sw_freeze       ),
        .o_cfg_start       (cfg_start       ), // config module start
        .o_gaussian_enable (gaussian_enable ),
        .o_sobel_enable    (sobel_enable    ),
        .o_pipe_flush      (pipe_flush      )
    );
    
    //---------------------------------------------------
    //                 Camera Block:
    //---------------------------------------------------
    assign io_cam_scl = (o_cam_scl) ? 1'bz : 1'b0;
    assign io_cam_sda = (o_cam_sda) ? 1'bz : 1'b0;
    assign i_cam_scl  = io_cam_scl;
    assign i_cam_sda  = io_cam_sda;
    assign o_cam_rstn = 1'b1;
    assign o_cam_pwdn = 1'b0;  
    
    cam_top 
    #(.T_CFG_CLK(8))
    cam_i (
        .i_cfg_clk          (clk_100MHz             ),
        .i_rstn             (sync_rstn_PS           ),
        .o_sof              (sof                    ),
        // OV7670 external inputs    
        .i_cam_pclk         (i_cam_pclk             ),
        .i_cam_vsync        (i_cam_vsync            ),
        .i_cam_href         (i_cam_href             ),
        .i_cam_data         (i_cam_data             ),
        // i2c bidirectional pins
        .i_scl              (i_cam_scl              ),
        .i_sda              (i_cam_sda              ),
        .o_scl              (o_cam_scl              ),
        .o_sda              (o_cam_sda              ),
        // Controls
        .i_cfg_init         (cfg_start              ),
        .o_cfg_done         (cfg_done               ),
        // output buffer read interface
        .i_obuf_rclk        (clk_100MHz             ),
        .i_obuf_rstn        (sync_rstn_PS           ),
        .i_obuf_rd          (cam_obuf_rd            ),
        .o_obuf_data        (cam_obuf_rdata         ),
        .o_obuf_empty       (),  
        .o_obuf_almostempty (cam_obuf_almostempty   ),  
        .o_obuf_fill        ()
    );

    //---------------------------------------------------
    //               Greyscale Converter:
    //---------------------------------------------------
    pp_preprocess pp_i (
        .i_clk         (clk_100MHz              ),
        .i_rstn        (sync_rstn_PS            ),
        .i_flush       (pipe_flush | sw_freeze  ),
        // greyscale algorithm enable
        .i_sw_mode     (sw_mode                 ),
        // input interface
        .o_rd          (cam_obuf_rd             ),
        .i_data        (cam_obuf_rdata          ),
        .i_almostempty (cam_obuf_almostempty    ),
        // output buffer interface
        .i_rd          (pp_obuf_rd              ),
        .o_data        (pp_obuf_rdata           ),
        .o_fill        (), 
        .o_almostempty (pp_obuf_almostempty     )
    );

    //---------------------------------------------------
    //                Gaussian Operator:
    //---------------------------------------------------
    ps_gaussian_top gaussian_i (
        .i_clk              (clk_100MHz             ),
        .i_rstn             (sync_rstn_PS           ),
        .i_enable           (gaussian_enable        ),
        .i_flush            (pipe_flush | sw_freeze ),
        .i_data             (pp_obuf_rdata          ),
        .i_almostempty      (pp_obuf_almostempty    ),
        .o_rd               (pp_obuf_rd             ),
        .i_obuf_rd          (gssn_obuf_rd           ),
        .o_obuf_data        (gssn_obuf_rdata        ),
        .o_obuf_fill        (),
        .o_obuf_full        (),
        .o_obuf_almostfull  (),
        .o_obuf_empty       (),
        .o_obuf_almostempty (gssn_obuf_almostempty  )
    );

    //---------------------------------------------------
    //                Sobel Operator:
    //---------------------------------------------------
    ps_sobel_top sobel_i (
        .i_clk              (clk_100MHz             ),
        .i_rstn             (sync_rstn_PS           ),
        .i_enable           (sobel_enable           ),
        .i_flush            (pipe_flush | sw_freeze ),
        .i_threshold        (sobel_threshold        ),
        .i_data             (gssn_obuf_rdata        ),
        .i_almostempty      (gssn_obuf_almostempty  ),
        .o_rd               (gssn_obuf_rd           ),
        .i_obuf_rd          (sobel_obuf_rd          ),
        .o_obuf_data        (sobel_obuf_rdata       ),
        .o_obuf_fill        (),
        .o_obuf_full        (),
        .o_obuf_almostfull  (),
        .o_obuf_empty       (),
        .o_obuf_almostempty (sobel_obuf_almostempty )
    );

    //---------------------------------------------------
    //                 Memory Interface:
    //---------------------------------------------------
    mem_interface 
    #(  .DATA_WIDTH (12),
        .BRAM_DEPTH (307200) 
    )
    mem_i(
        .i_clk         (clk_100MHz             ), // 125 MHz board clock
        .i_rstn        (sync_rstn_PS           ), // active-low sync reset
        .i_flush       (pipe_flush | sw_freeze ),
        // Input FIFO read interface
        .o_rd          (sobel_obuf_rd          ),
        .i_rdata       (sobel_obuf_rdata       ),
        .i_almostempty (sobel_obuf_almostempty ),
        // frame buffer read interface
        .i_rclk        (clk_25MHz              ),
        .i_raddr       (framebuf_raddr         ),
        .o_rdata       (framebuf_rdata         )
    ); 

    //---------------------------------------------------
    //                 Display Interface:
    //---------------------------------------------------
    display_interface 
    display_i(
        .i_p_clk            (clk_25MHz          ), // 25 MHz display clock
        .i_rstn             (btn_rstn           ), 
        .i_sw_mode          (sw_mode            ), // mode; color or greyscale
        // frame buffer read interface
        .o_raddr            (framebuf_raddr     ),
        .i_rdata            (framebuf_rdata     ),
        // HDMI Interface
        .i_hdmi_int         (i_hdmi_int         ),
        .i_hdmi_spdif_out   (i_hdmi_spdif_out   ),
        .o_hdmi_spdif       (o_hdmi_spdif       ),
        .o_hdmi_vsync       (o_hdmi_vsync       ),
        .o_hdmi_hsync       (o_hdmi_hsync       ),
        .o_hdmi_de          (o_hdmi_de          ),
        .o_hdmi_clk         (o_hdmi_clk         ),
        .o_hdmi_data        (o_hdmi_data        ),
        .o_hdmi_iic_scl     (o_hdmi_iic_scl     ),
        .io_hdmi_iic_sda    (io_hdmi_iic_sda    )
    );

endmodule