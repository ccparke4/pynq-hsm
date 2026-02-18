`timescale 1ns/1ps

// ==================================================================
// NIST SP 800-90B based health tests for TRNG sources
// Startup and Continuous Tests on post Von-Neumann debiased stream

// 1. Repetition Count Test - RCT
//      - Should never produce same bit 32 times in a row, if so oscillators are likely stuck
// 2. Adaptive Proportion Test - APT
//      - Over a 512 moving windows, count how many "=1". A fair src sould produce ~512/2 = 256 ones
//      - Count fails? outside threshold, something is wrong with source
//      - Catches bias drift
//   
// ==================================================================

(* KEEP_HIERIARCHY = "true" *)
module trng_health #(
    parameter integer RCT_CUTOFF = 32,
    parameter integer APT_WINDOW_SIZE = 512,
    parameter integer APT_LOW = 166,
    parameter integer APT_HIGH = 346
)(
    input   wire    clk,
    input   wire    rst_n,
    input   wire    valid_bit,
    input   wire    valid_strobe,
    input   wire    clear,
    output  reg     rct_fail,
    output  reg     apt_fail,
    output  reg     health_fail
);

    assign health_fail = rct_fail | apt_fail;

    // ===== Repetition Count Test (RCT) =====
    reg [5:0]   rct_count;    // 6 bits to count up to 32
    reg         rct_prev_bit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            rct_prev_bit    <= 1'b0;
            rct_count       <= 6'd0;
            rct_fail        <= 1'b0;
        end
        else if (valid_strobe) begin
            if (valid_bit == rct_prev_bit) begin
                if (rct_count >= 6'(RCT_CUTOFF))
                    rct_fail   <= 1'b1;         // Fail if we hit cutoff
                else
                    rct_count  <= rct_count + 1; // Increment count
            end
            else begin
                rct_count       <= 6'd0;
                rct_prev_bit    <= valid_bit; // Update last bit
            end 
        end
    end

    // ===== Adaptive Proportion Test (APT) =====
    localparam APT_CNT_W = $clog2(APT_WINDOW_SIZE + 1);
    
    reg [APT_WINDOW_SIZE-1 : 0] apt_buffer;
    reg [APT_CNT_W-1 : 0]       apt_ones_count;
    reg [APT_CNT_W-1 : 0]       apt_fill_count;
    reg                         apt_window_full;

    wire apt_leaving_bit = apt_buffer[0];
    wire [APT_CNT_W-1 : 0] apt_nxt_ones = apt_window_full ?
        (apt_ones_count + APT_CNT_W'(valid_bit) - APT_CNT_W'(apt_leaving_bit)) :
        (apt_ones_count + APT_CNT_W'(valid_bit));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            apt_buffer      <= '0;
            apt_ones_count  <= '0;
            apt_fill_count  <= '0;  
            apt_window_full <=  1'b0;
            apt_fail        <=  1'b0;
        end
        else if (valid_strobe) begin
            apt_buffer      <= {apt_buffer[APT_WINDOW_SIZE-2:0], valid_bit}; // Shift in new bit
            apt_ones_count  <= apt_nxt_ones; // Update ones count

            if (!apt_window_full) begin
                if (apt_fill_count == APT_WINDOW_SIZE - 1)
                    apt_window_full <= 1'b1; // Mark window as full once we have enough bits
                else
                    apt_fill_count <= apt_fill_count + 1; // Increment fill count
            end

            if (apt_window_full) begin
                if (apt_nxt_ones < APT_CNT_W'(APT_LOW) || apt_nxt_ones > APT_CNT_W'(APT_HIGH))
                    apt_fail <= 1'b1; // Fail if count is outside thresholds
            end
        end
    end


endmodule