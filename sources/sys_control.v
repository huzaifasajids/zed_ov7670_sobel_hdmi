// sys_control.v
//
// This module acts as an interface between board inputs and
// pipeline control.
//
//
`default_nettype none
//
`define MODE_PASSTHROUGH 0
//
module sys_control
    (
    input  wire       i_sysclk,
    input  wire       i_rstn,

    input  wire       i_sof,

    input  wire       i_sw_mode,
    input  wire       i_sw_gaussian,
    input  wire       i_sw_sobel,
    input  wire       i_sw_freeze,

    output reg        o_cfg_start,
    output reg        o_pipe_flush,

    output wire       o_gaussian_enable,
    output wire       o_sobel_enable
    );

// =============================================================
//              Parameters, Registers, and Wires
// =============================================================
    reg        STATE;
    localparam STATE_CFG    = 0,
               STATE_ACTIVE = 1;

    reg        FLUSH_STATE;
    localparam FLUSH_IDLE   = 0, 
               FLUSH_ACTIVE = 1;

    reg        sw_gaussian_q1, sw_gaussian_q2;
    wire       delta_sw_gaussian;

    reg        sw_sobel_q1, sw_sobel_q2;
    wire       delta_sw_sobel;

    reg        sw_freeze_q1, sw_freeze_q2;
    wire       delta_sw_freeze;

    reg        sw_mode_q1, sw_mode_q2;
    wire       delta_sw_mode;

// =============================================================
//                        Implementation:
// =============================================================

//
// Configure camera to ROM values on startup or reset
//
    always@(posedge i_sysclk) begin
        if(!i_rstn) begin
            o_cfg_start <= 0;
            STATE <= STATE_CFG;
        end
        else begin
            case(STATE)
                STATE_CFG: begin
                    o_cfg_start <= 1;
                    STATE <= STATE_ACTIVE;
                end

                STATE_ACTIVE: begin
                    o_cfg_start <= 0;
                    STATE <= STATE_ACTIVE;
                end
            endcase
        end
    end

//
// Filter enables
//
assign o_gaussian_enable = (i_sw_mode == `MODE_PASSTHROUGH) ? 0 : i_sw_gaussian;
assign o_sobel_enable    = (i_sw_mode == `MODE_PASSTHROUGH) ? 0 : i_sw_sobel;

// Enable edge detectors
// 
    always@(posedge i_sysclk) begin
        if(!i_rstn) begin
            {sw_gaussian_q1, sw_gaussian_q2} <= 2'b0;
        end
        else begin
            {sw_gaussian_q1, sw_gaussian_q2} <= {i_sw_gaussian, sw_gaussian_q1};
        end
    end
    assign delta_sw_gaussian = (sw_gaussian_q1 != sw_gaussian_q2);

    always@(posedge i_sysclk) begin
        if(!i_rstn) begin
            {sw_sobel_q1, sw_sobel_q2} <= 2'b0;
        end
        else begin
            {sw_sobel_q1, sw_sobel_q2} <= {i_sw_sobel, sw_sobel_q1};
        end
    end
    assign delta_sw_sobel = (sw_sobel_q1 != sw_sobel_q2);

    always@(posedge i_sysclk) begin
        if(!i_rstn) begin
            {sw_freeze_q1, sw_freeze_q2} <= 2'b0;
        end
        else begin
            {sw_freeze_q1, sw_freeze_q2} <= {i_sw_freeze, sw_freeze_q1};
        end
    end
    assign delta_sw_freeze = (sw_freeze_q1 != sw_freeze_q2);

    always@(posedge i_sysclk) begin
        if(!i_rstn) begin
            {sw_mode_q1, sw_mode_q2} <= 2'b0;
        end
        else begin
            {sw_mode_q1, sw_mode_q2} <= {i_sw_mode, sw_mode_q1};
        end
    end
    assign delta_sw_mode = (sw_mode_q1 != sw_mode_q2);

//
// Flush the pipeline if a filter is applied
// -> hold the flush until start of frame
//
    always@(posedge i_sysclk) begin
        if(!i_rstn) begin
            o_pipe_flush <= 0;
            FLUSH_STATE  <= FLUSH_IDLE;
        end
        else begin
//            if(i_mode != `MODE_PASSTHROUGH ) begin
                case(FLUSH_STATE)
                    FLUSH_IDLE: begin
                        o_pipe_flush <= 0;
                        FLUSH_STATE  <= (delta_sw_gaussian | delta_sw_sobel | delta_sw_freeze | delta_sw_mode) ? FLUSH_ACTIVE : FLUSH_IDLE;
                    end
    
                    FLUSH_ACTIVE: begin
                        o_pipe_flush <= 1;
                        FLUSH_STATE  <= (i_sof) ? FLUSH_IDLE : FLUSH_ACTIVE;
                    end
                endcase
//            end
//            else o_pipe_flush <= 0;
        end
    end

endmodule