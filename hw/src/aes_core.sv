`timescale 1ns/1ps

// =================================================================================
// arch             -> iterative - 1 rd per cycle
// key schedule     -> iteratively on key_valid strobe
// encryption       -> 14 rds 
// latency          -> 52 cycle key expansion + 14 cycles/block
// resources apprx  -> ~4k LUTs, ~1k FFs 
// FSM: IDLE -> KEY_EXP (52 cycles) -> READY -> ENCRYPT (14 cycles) -> DONE -> IDLE
// Refs: FIPS 197, NIST AES std.
// ==================================================================================


(* KEEP_HIERARCHY = "TRUE" *)   // prevent logic from merging
module aes_core (
    input   wire            clk,
    input   wire            rst_n,

    // key interface - WR 256'b key then asset key_valid pulse
    input   wire [255:0]    key,
    input   wire            key_valid,

    // data interface - WR plaintext then assery encrypt_start
    input   wire [127:0]    plaintext,
    input   wire            encrypt_start,  // strobe - begin encryption
    input   wire            clear,          // sync reset to IDLE

    // status
    output  reg             ready,           // key expanded, accepts encrypt_start
    output  reg             busy,            // either key exp or encryption in progress
    output  reg             done,            // ciphertext valid, pulse

    // output 
    output  reg [127:0]    ciphertext
);

// ====== AES Forward S-box ======
// synth to dist ROM / LUTs
// Vals from FIPS 197 Fig. 7
// ===============================

// 128'b buses to route data to/from 16 Sboxes
logic [127:0] sbox_in, sbox_out;

// gen 16 parallel S-boxes for SubBytes step
genvar i;
generate
    for (i = 0; i < 16; i = i + 1) begin : gen_subbytes
        // slice the bus into 8-bit chunks
        aes_sbox sbox (
            .in_byte(sbox_in[i*8 +: 8]),
            .out_byte(sbox_out[i*8 +: 8])
        );
    end
endgenerate

// feed state reg into SubBytes step during encryption rounds
// KEY_EXPAND path uses sub_word_in/out 
always_comb begin
    sbox_in = state_reg;  // default - feed state to S-boxes
end

// ============= ShiftRows ============
// r0: no shift          bytes 0, 4, 8, 12 -> stay
// r1: shift L1          bytes 1, 5, 9, 13 -> 5, 9, 13, 1
// r2: shift L2          bytes 2, 6, 10,14 -> 10, 14, 2, 6
// r3: shift L3          bytes 3, 7, 11,15 -> 15, 3, 7, 11
// =================================
logic [127:0] sub_shift_out;

always_comb begin
    // Row 0 - no shift
    sub_shift_out[127:120] = sbox_out[127:120];  // b0 <- b0
    sub_shift_out[95:88]   = sbox_out[95:88];    // b4 <- b4
    sub_shift_out[63:56]   = sbox_out[63:56];    // b8 <- b8
    sub_shift_out[31:24]   = sbox_out[31:24];    // b12 <- b12
    // Row 1 - shift L1
    sub_shift_out[119:112] = sbox_out[87:80];    // b1 <- b5
    sub_shift_out[87:80]   = sbox_out[55:48];    // b5 <- b9
    sub_shift_out[55:48]   = sbox_out[23:16];    // b9 <- b13
    sub_shift_out[23:16]   = sbox_out[119:112];  // b13 <- b1
    // Row 2 - shift L2
    sub_shift_out[111:104] = sbox_out[47:40];    // b2  <- b10
    sub_shift_out[79:72]   = sbox_out[15:8];     // b6  <- b14
    sub_shift_out[47:40]   = sbox_out[111:104];  // b10 <- b2
    sub_shift_out[15:8]    = sbox_out[79:72];    // b14 <- b6
    // Row 3 - shift L3
    sub_shift_out[103:96]  = sbox_out[7:0];      // b3  <- b15
    sub_shift_out[71:64]   = sbox_out[103:96];   // b7  <- b3
    sub_shift_out[39:32]   = sbox_out[71:64];    // b11 <- b7
    sub_shift_out[7:0]     = sbox_out[39:32];    // b15 <- b11
end

// ===== MixColumns: GF(2^8) matrix mult =====
// applied to ech of 4 cols of sub_shift_out
// skipped on rd14
// ===========================================

// xtime: mult by 2 in GF(2^8) - irreducible poly x^8 + x^4 + x^3 + x + 1
function automatic logic [7:0] xtime(input logic [7:0] byte_in);
    return byte_in[7] ? ((byte_in << 1) ^ 8'h1b) : (byte_in << 1);
endfunction

// mix one 32'b column
// GF matrix:  [2 3 1 1]
//             [1 2 3 1]
//             [1 1 2 3]
//             [3 1 1 2]
// opt: tmp = a0 ^ a1 ^ a2 ^ a3, each out = ai ^ tmp ^ xtime(ai ^ aj) 
function automatic logic [31:0] mix_col(input logic [31:0] col_in);
    logic [7:0] a0, a1, a2, a3, tmp;

    a0 = col_in[31:24];
    a1 = col_in[23:16];
    a2 = col_in[15:8];
    a3 = col_in[7:0];
    
    tmp = a0 ^ a1 ^ a2 ^ a3;

    mix_col[31:24] = xtime(a0 ^ a1) ^ a0 ^ tmp; // out0
    mix_col[23:16] = xtime(a1 ^ a2) ^ a1 ^ tmp; // out1
    mix_col[15:8]  = xtime(a2 ^ a3) ^ a2 ^ tmp; // out2
    mix_col[7:0]   = xtime(a3 ^ a0) ^ a3 ^ tmp; // out3
endfunction

logic [127:0] mix_out;

always_comb begin
    mix_out[127:96] = mix_col(sub_shift_out[127:96]);   // col0
    mix_out[95:64]  = mix_co(sub_shift_out[95:64]);    // col1
    mix_out[63:32]  = mix_col(sub_shift_out[63:32]);    // col2
    mix_out[31:0]   = mix_col(sub_shift_out[31:0]);     // col3
end

// ============ Key Schedule ============
// AES-256: W[0..7] loaded dir from key input
//          W[8..59] generated iteratively from W[i-1] and W[i-8]
//
// Rules (FIPS 197, Sec. 5.2):
//   i % 8 == 0: W[i] = W[i-8] XOR sub_word(rot_word(W[i-1])) XOR Rcon[i/8]
//   i % 8 == 4: W[i] = W[i-8] XOR sub_word(W[i-1])
//   else:        W[i] = W[i-8] XOR W[i-1]
// ====================================

// RotWord: left rotate 32'b word by 8 bits
function automatic logic [31:0] rot_word(input logic [31:0] word_in);
    return {word_in[23:0], word_in[31:24]};
endfunction 

// Rcon lookup - only indices 1-7 needed for AES-256 key expansion
function automatic logic [31:0] rcon(input logic [3:0] index);
    case (index)
        1: rcon = 32'h01000000;
        2: rcon = 32'h02000000;
        3: rcon = 32'h04000000;
        4: rcon = 32'h08000000;
        5: rcon = 32'h10000000;
        6: rcon = 32'h20000000;
        7: rcon = 32'h40000000;
        default: rcon = 32'h0; // should not happen
    endcase
endfunction

// Subword: 4 dedicated S-boxes for key schedule path
// seperate from gen_subbytes - active during KEY_EXPAND, idle during ENCRYPT
logic [31:0] sub_word_in, sub_word_out;

genvar j;
generate
    for (j = 0; j < 4; j = j + 1) begin : gen_subword
        aes_sbox sbox (
            .in_byte(sub_word_in[31 - j*8 -: 8]),
            .out_byte(sub_word_out[31 - j*8 -: 8])
        );
    end
endgenerate

// key word storage: W[0..59], 60 x 32'b
logic [31:0] W [0:59];

// current expanded key word being computed
wire [5:0]  ks_idx      = key_idx;              // what word?
wire [31:0] ks_prev     = W[key_idx - 1];       // W[i-1]
wire [31:0] ks_prev8    = W[key_idx - 8];       // W[i-8]
wire [3:0]  rcon_idx   = {1'b0, key_idx[5:3]}; // i / 8

// Drive sub_word_in from key schedule
// rotate before subword when i % 8 == 0
always_comb begin
    if (ks_idx[2:0] == 3'd0) begin
        sub_word_in = rot_word(ks_prev);
    end else begin
        sub_word_in = ks_prev;
    end
end

// comb next key word 
wire [31:0] ks_tmp = (key_idx[2:0] == 3'd0) ? (sub_word_out ^ rcon(rcon_idx)) :
                                              (key_idx[2:0] == 3'd4) ? sub_word_out :
                                              ks_prev;


// ====== Rd key Mux =============================================
// {W[4r], W[4r+1], W[4r+2], W[4r+3]} fed to state reg each rd
// ================================================================
wire [127:0] round_key = {
    W[{round_cnt, 2'b00}],
    W[{round_cnt, 2'b01}],
    W[{round_cnt, 2'b10}],
    W[{round_cnt, 2'b11}]
};

// ============ FSM State Encoding ============
// let synthesis choose best encoding
localparam [2:0]
    IDLE        = 3'd0,
    KEY_EXPAND  = 3'd1,
    READY       = 3'd2,
    ENCRYPT     = 3'd3,
    DONE        = 3'd4;

reg [2:0] state;
reg [5:0] key_idx;      // counts from 0 to 59 during KEY_EXP
reg [3:0] round_cnt;    // counts from 0 to 14 during ENCRYPT
reg [127:0] state_reg;  // holds current state during encryption rounds

// =========== FSM & Datapath ============
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // async reset - go to IDLE, clear all regs
        state       <= IDLE;
        ready       <= 0;
        busy        <= 0;
        done        <= 0;
        key_idx     <= 0;
        round_cnt   <= 0;
        state_reg   <= '0;
        ciphertext  <= '0;
    end else begin
        done <= 0; // default - clear done pulse

        case (state)
            // IDLE -------------------------------
            IDLE: begin
                // load [0..7] from key input directly
                if (key_valid) begin
                    W[0] <= key[255:224];
                    W[1] <= key[223:192];
                    W[2] <= key[191:160];
                    W[3] <= key[159:128];
                    W[4] <= key[127:96];
                    W[5] <= key[95:64];
                    W[6] <= key[63:32];
                    W[7] <= key[31:0];

                    key_idx <= 8; // next word to generate
                    state   <= KEY_EXP;
                    busy    <= 1;
                end
            end
            // KEY_EXPAND -------------------------
            // one key word comp'd per cycle
            // ------------------------------------
            KEY_EXPAND: begin
                W[key_idx] <= ks_prev8 ^ ks_tmp; // comb logic

                if (key_idx == 59) begin
                    busy  <= 0;
                    state <= READY;
                    ready <= 1; // key expansion done, signal ready
                end else begin
                    key_idx <= key_idx + 1;
                end
            end
            // READY ------------------------------
            READY: begin
                if (key_valid) begin
                    // accept new key w/o waiting for encrypt
                    W[0] <= key[255:224];
                    W[1] <= key[223:192];
                    W[2] <= key[191:160];
                    W[3] <= key[159:128];
                    W[4] <= key[127:96];
                    W[5] <= key[95:64];
                    W[6] <= key[63:32];
                    W[7] <= key[31:0];
                    key_idx <= 8; // next word to generate
                    busy    <= 1;
                    ready   <= 0;
                    state   <= KEY_EXPAND;
                end else if (encrypt_start) begin
                    // init. AddRoundKey with round 0
                    state_reg <= plaintext ^ {W[0], W[1], W[2], W[3]};
                    round_cnt <= 1;
                    busy      <= 1;
                    ready     <= 0;
                    state     <= ENCRYPT;
                end
            end

            // ENCRYPT ----------------------------
            // Rds 1-13: SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
            // Rd 14:   SubBytes -> ShiftRows -> AddRoundKey (no MixColumns)
            // ------------------------------------
            ENCRYPT: begin
                if (round_cnt < 14) begin
                    // Rds 1-13
                    state_reg <= mix_out ^ round_key; // combine MixColumns out with round key
                    round_cnt <= round_cnt + 1;
                end else begin
                    // Rd 14 - no MixColumns
                    ciphertext <= sub_shift_out ^ round_key; // final ciphertext output
                    busy       <= 0;
                    done       <= 1; // pulse done when ciphertext is valid
                    state      <= DONE;
                end
            end
            // DONE -------------------------------
            DONE: begin
                // wait for clear to return to IDLE
                if (clear) begin
                    state <= READY;
                    ready <= 1;
                end
            end

            default: state <= IDLE; // should not happen

        endcase
    end
end
endmodule