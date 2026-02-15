`timescale 1ns/1ps
// here we sample the TRNG, N osc of different lengths

(* KEEP_HIERARCHY = "TRUE" *)
module trng_sampler(
    input   wire        clk,
    input   wire        rst_n,

    // control
    input   wire        enable,         // enable oscillators
    input   wire        sample_trig,    // trigger single sample
    input   wire        clear,          // clear accumulated data

    // outputs
    output  wire [3:0]  raw_osc,        // raw oscillator outputs dbg
    output  reg  [31:0] random_out,     // accumulatd random data
    output  reg  [31:0] sample_count,   // number of samples
    output  wire        osc_running     // osc status
);

    // osc outputs
    wire osc0, osc1, osc2, osc3;

    // inst. 4 diff. oscillators w/ diffrent prime stage counts
    // different lengths = different freqs = uncorrelated jitter
    ring_osc #(.STAGES(13)) ro0 (.enable(enable), .osc_out(osc0));
    ring_osc #(.STAGES(17)) ro1 (.enable(enable), .osc_out(osc1));
    ring_osc #(.STAGES(19)) ro2 (.enable(enable), .osc_out(osc2));
    ring_osc #(.STAGES(23)) ro3 (.enable(enable), .osc_out(osc3));

    // raw out
    assign raw_osc = {osc3, osc2, osc1, osc0};
    assign osc_running = enable;

    // synchronizers for metastability (simple 2-stage)
    reg [3:0] osc_sync1, osc_sync2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            osc_sync1 <= 4'b0;
            osc_sync2 <= 4'b0;
        end else begin
            osc_sync1 <= raw_osc;
            osc_sync2 <= osc_sync1;     // sync avoiding metastability issues
        end
    end

    wire raw_bit = ^osc_sync2;          // XOR all bits

    // --- Von Neumann Debiaser ---
    // we need to capture 2 bits to make 1 decision
    reg [1:0]   vn_buffer;      // stores pair of bits
    reg         vn_count;       // track if we have 0,1,2 bits
    reg         valid_bit;      // final debiased bit
    reg         valid_strobe;   // pulse when valid_bit is ready

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vn_count        <= '0;
            valid_strobe    <= '0;
            valid_bit       <= '0;
        end else if (enable) begin
            valid_strobe <= 0;

            // simple state machine: toggle between capturing bit A & B
            vn_count <= ~vn_count;  // toggle count each cycle

            if (vn_count == 0) begin
                vn_buffer[0] <= raw_bit;   // capture bit A
            end else begin
                vn_buffer[1] <= raw_bit;    // capture bit B

                // analyze the pair (Von Neumann logic)
                if (vn_buffer[0] == 1'b0 && raw_bit == 1'b1) begin
                    valid_bit <= 0;
                    valid_strobe <= 1;  // new bit ready
                end else if (vn_buffer[0] == 1'b1 && raw_bit == 1'b0) begin
                    valid_bit <= 1;
                    valid_strobe <= 1;  // new bit ready
                end
                // if 00 or 11 do nothing and discard bits (no strobe)
            end
        end
    end

    // --- Output Accumulator ---
    // only shift in data if SW asked for it AND we have a valid de-biased bit

    // detect SW req.
    reg sample_trig_d;
    always_ff @(posedge clk) sample_trig_d <= sample_trig;
    wire software_request = sample_trig & ~sample_trig_d;  // rising edge detect

    reg waiting_for_bit;  // track if we're waiting for a valid bit after SW req

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            random_out   <= '0;
            sample_count <= '0;
            waiting_for_bit <= '0;
        end else begin
            // If sw asks, rememberwe are waiting
            if (software_request) waiting_for_bit <= 1;

            // if we are waiting AND the debiaser gives a valid bit...
            if (waiting_for_bit && valid_strobe) begin
                random_out <= {random_out[30:0], valid_bit};  // shift in new bit
                sample_count <= sample_count + 1;
                waiting_for_bit <= 0;  // done with this request
            end
        end
    end


    // sample trigger edge detection
    reg sample_trig_d;
    wire sample_pulse;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            sample_trig_d <= 1'b0;
        else
            sample_trig_d <= sample_trig;
    end

    assign sample_pulse = sample_trig & ~sample_trig_d;

    // bit accumulators - shift in XOR of all osc
    wire entropy_bit = ^osc_sync2;  // all 4 bits

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            random_out   <= 32'h0;
            sample_count <= 32'h0;
        end else if (clear) begin
            random_out   <= 32'h0;
            sample_count <= 32'h0;
        end else if (sample_pulse && enable) begin
            // shift in new entropy bit
            random_out   <= {random_out[30:0], entropy_bit};
            sample_count <= sample_count + 1;
        end
    end

endmodule