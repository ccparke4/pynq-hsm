`timescale 1ns/1ps
// Entropy source for TRNG

(* KEEP_HIERARCHY = "TRUE" *)
module ring_osc #(
    parameter STAGES = 13       // must be odd
)(
    input   wire enable,        // enable oscillation
    output  wire osc_out        // osc output
);

    // odd # of stages
    initial begin
        if (STAGES % 2 == 0) begin
            $error("STAGES MUST BE ODD FOR A RING OSCILLATOR!!");
        end
    end

    (* ALLOW_COMBINATORIAL_LOOPS = "TRUE" , DONT_TOUCH = "TRUE" *) 
    wire [STAGES-1:0] chain;

    genvar i;
    generate
        for (i = 0; i < STAGES; i++) begin
            if (i == 0) begin
                // stage1 - feedback from last gated by enable
                (* DONT_TOUCH = "TRUE" *)
                LUT2 #(
                    .INIT(4'b0100)  // out = enable & ~input
                ) lut_inst (
                    .I0(chain[STAGES-1]),
                    .I1(enable),
                    .O(chain[0])
                );
            end else begin
                // remaining is just inverters
                (* DONT_TOUCH = "TRUE" *)
                LUT1 #(
                    .INIT(2'b01)    // out = ~in
                ) lut_inst (
                    .I0(chain[i-1]),
                    .O(chain[i])
                );
            end
        end
    endgenerate

    assign osc_out = chain[STAGES-1];

endmodule