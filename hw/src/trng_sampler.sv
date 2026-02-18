`timescale 1ns/1ps

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
    output  reg  [31:0] random_out,     // accumulated random data
    output  reg  [31:0] sample_count,   // number of samples
    output  wire        osc_running,     // osc status

    // healt monitor (post VN biased stream)
    output  wire        health_valid_bit,   // valid bit from health monitor
    output  wire        health_valid_strobe // pulse when health monitor has valid bit
);

    // --- CONFIG ---
    // Decimation: Wait N cycles between samples to let jitter accumulate
    // 7 means sampling every 8th (100MHz / 8 = 12.5MHz)
    localparam DECIMATION_WAIT = 7;

    // --- OSCILLATORS ---
    wire osc0, osc1, osc2, osc3;

    // inst. 4 diff. oscillators w/ diffrent prime stage counts
    ring_osc #(.STAGES(13)) ro0 (.enable(enable), .osc_out(osc0));
    ring_osc #(.STAGES(17)) ro1 (.enable(enable), .osc_out(osc1));
    ring_osc #(.STAGES(19)) ro2 (.enable(enable), .osc_out(osc2));
    ring_osc #(.STAGES(23)) ro3 (.enable(enable), .osc_out(osc3));

    // raw out
    assign raw_osc = {osc3, osc2, osc1, osc0};
    assign osc_running = enable;

    // --- SYNCHRONIZER & XOR ---
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

    // --- DECIMATOR ---
    reg [3:0] dec_counter;
    reg [3:0] dec_threshold;            // random each cycle
    reg       sample_pulse;             // pulse when we want to sample a bit

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_counter     <= '0;
            sample_pulse    <= 0;
            dec_threshold   <= 4'd7;
        end else if(enable) begin
            sample_pulse    <= 0;
            if (dec_counter >= dec_threshold) begin
                dec_counter     <= '0;
                dec_threshold   <= {3'd6, raw_bit} + 4'd6;  // 6-7 cycles
                sample_pulse    <= 1;
            end else begin
                dec_counter <= dec_counter + 1;
            end
        end else begin
            // SAFETY FIX: Ensure pulse is killed if enable drops
            dec_counter  <= '0;
            sample_pulse <= 0;
        end
    end

    // --- VON NEUMANN DEBIASER ---
    reg [1:0]   vn_buffer;      // stores pair of bits
    reg         vn_state;       // 0=waiting, 1=waiting for bit
    reg         vn_valid_bit;   // random bit 
    reg         vn_valid_pulse; // pulse when valid_bit is found

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vn_state       <= '0;
            vn_valid_pulse <= '0;
            vn_valid_bit   <= '0;
            vn_buffer      <= '0;
        end else if (sample_pulse) begin
            vn_valid_pulse <= 0;

            if (vn_state == 0) begin
                vn_buffer[0] <= raw_bit;
                vn_state     <= 1;
            end else begin
                // have bit A (buffer[0]) and Bit B (raw_bit)
                vn_state <= 0;

                // Von Neumann Logic:
                // 0 -> 1 : output 0
                // 1 -> 0 : output 1
                // else: discard
                if (vn_buffer[0] == 0 && raw_bit == 1) begin
                    vn_valid_bit   <= 0; 
                    vn_valid_pulse <= 1; // valid bit found
                end else if (vn_buffer[0] == 1 && raw_bit == 0) begin
                    vn_valid_bit   <= 1; 
                    vn_valid_pulse <= 1; // valid bit found
                end
            end
        end else begin
            vn_valid_pulse <= 0;   // clear pulse when not sampling
        end
    end

    // NEW - added health monitor tabs to internal VN signals
    assign health_valid_bit     = vn_valid_bit;
    assign health_valid_strobe  = vn_valid_pulse;


    // --- Output Accumulator ---
    reg [5:0] bit_count;   // counts from 0 -> 32
    reg       valid;       // high when random_out is valid

    // detect rising edge of sample_trig
    reg trig_d;
    always_ff @(posedge clk) trig_d <= sample_trig;
    wire start_collection = (sample_trig && !trig_d); // pulse on rising edge

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            random_out   <= '0;
            sample_count <= '0;
            bit_count    <= '0;
            valid        <= 0;
        end else begin
            // 1. Start Collection
            if (start_collection) begin
                valid     <= 0;    // clear valid until we have a new sample
                bit_count <= 0;
            end

            // 2. Shift in bits (if not done)
            if (!valid && vn_valid_pulse) begin
                random_out <= {random_out[30:0], vn_valid_bit}; // shift in new bit
                bit_count  <= bit_count + 1; 
            end

            // 3. Finish
            if (bit_count == 32 && !valid) begin
                valid        <= 1;    // new random number ready
                sample_count <= sample_count + 1;
            end
        end
    end

endmodule