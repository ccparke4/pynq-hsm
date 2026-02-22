`timescale 1ns/1ps

// ======================================================
//   Register Map:
//     0x00  AES_CTRL    [W]   bit0=key_load, bit1=encrypt, bit2=clear
//     0x04  AES_STATUS  [R]   bit0=ready, bit1=busy, bit2=done_latched
//     0x10  KEY_W0      [W]   key[255:224]
//     0x14  KEY_W1      [W]   key[223:192]
//     0x18  KEY_W2      [W]   key[191:160]
//     0x1C  KEY_W3      [W]   key[159:128]
//     0x20  KEY_W4      [W]   key[127:96]
//     0x24  KEY_W5      [W]   key[95:64]
//     0x28  KEY_W6      [W]   key[63:32]
//     0x2C  KEY_W7      [W]   key[31:0]
//     0x30  PTEXT_W0    [W]   plaintext[127:96]
//     0x34  PTEXT_W1    [W]   plaintext[95:64]
//     0x38  PTEXT_W2    [W]   plaintext[63:32]
//     0x3C  PTEXT_W3    [W]   plaintext[31:0]
//     0x40  CTEXT_W0    [R]   ciphertext[127:96]
//     0x44  CTEXT_W1    [R]   ciphertext[95:64]
//     0x48  CTEXT_W2    [R]   ciphertext[63:32]
//     0x4C  CTEXT_W3    [R]   ciphertext[31:0] 
// 
// SW Flow:
//  1. write KEY_W[0-7] 
//  2. write AES_CTRL = 0x1 (key_load)
//  3. write AES_CTRL = 0x0 (deassert)
//  4. poll AES_STATUS until b0=1 (ready)
//  5. write PTEXT_W[0-3]
//  6. write AES_CTRL = 0x2 (encrypt)
//  7. Write AES_CTRL = 0x0 (deassert)
//  8. Poll AES_STATUS until b2=1 (done_latched)
//  9. read CTEXT_W[0-3]
//  10. Writ AES_CTRL = 0x4 (clear done latch)
// ======================================================

module aes_axi_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 7
)(
        // global clk & rst
    input wire S_AXI_ACLK,
    input wire S_AXI_ARESETN,

    // write address channel (external IP says "I want to write to addr X")
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]  S_AXI_AWADDR,           // Address
    input  wire [2 : 0]                     S_AXI_AWPROT,           // protection type
    input  wire                             S_AXI_AWVALID,          // master says "Address is valid!?"
    output wire                             S_AXI_AWREADY,          // slave says  "I'm ready for address!?"

    // write data channnel (external IP says "heres the data to write")
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0]      S_AXI_WDATA,        // Data
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0]  S_AXI_WSTRB,        // Byte enables, not using currently
    input  wire                                 S_AXI_WVALID,       // Master "data is valid"   
    output wire                                 S_AXI_WREADY,       // slave "I'm ready for data"

    // Write response channel  (Core IP says "I'm done writing"... next?)
    output wire [1 : 0]     S_AXI_BRESP,                            // status -> 00 = OKAY!
    output wire             S_AXI_BVALID,                           // slave "response is valid"
    input  wire             S_AXI_BREADY,
 
    // Read address channel (External IP says "I want to read address Y")
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]  S_AXI_ARADDR,            // address
    input  wire [2 : 0]                     S_AXI_ARPROT,           
    input  wire                             S_AXI_ARVALID,          // Master "address valid?"
    output wire                             S_AXI_ARREADY,          // slave "Im ready?"

    // read data channel (Core IP says "heres the value")
    output wire [C_S_AXI_DATA_WIDTH-1 : 0]  S_AXI_RDATA,            // data
    output wire [1 : 0]                     S_AXI_RRESP,            // status
    output wire                             S_AXI_RVALID,           // slave "data valid"
    input  wire                             S_AXI_RREADY             // master "i'm ready"
);

    // Register addresses ==============================
    localparam ADDR_CTRL     = 5'h00; // 0x00
        localparam ADDR_STATUS   = 5'h01; // 0x04
        // 0x08, 0x0C reserved
        localparam ADDR_KEY_W0   = 5'h04; // 0x10
        localparam ADDR_KEY_W1   = 5'h05; // 0x14
        localparam ADDR_KEY_W2   = 5'h06; // 0x18
        localparam ADDR_KEY_W3   = 5'h07; // 0x1C
        localparam ADDR_KEY_W4   = 5'h08; // 0x20
        localparam ADDR_KEY_W5   = 5'h09; // 0x24
        localparam ADDR_KEY_W6   = 5'h0A; // 0x28
        localparam ADDR_KEY_W7   = 5'h0B; // 0x2C
        localparam ADDR_PTEXT_W0 = 5'h0C; // 0x30
        localparam ADDR_PTEXT_W1 = 5'h0D; // 0x34
        localparam ADDR_PTEXT_W2 = 5'h0E; // 0x38
        localparam ADDR_PTEXT_W3 = 5'h0F; // 0x3C
        localparam ADDR_CTEXT_W0 = 5'h10; // 0x40
        localparam ADDR_CTEXT_W1 = 5'h11; // 0x44
        localparam ADDR_CTEXT_W2 = 5'h12; // 0x48
        localparam ADDR_CTEXT_W3 = 5'h13; // 0x4C

    // SW writeable registers ================================
    logic [31:0] slv_ctrl;
    logic [31:0] slv_key   [0:7];    
    logic [31:0] slv_ptext [0:3];

    // Control bit extraction ================================
    wire ctrl_key_load = slv_ctrl[0];
    wire ctrl_encrypt  = slv_ctrl[1];
    wire ctrl_clear    = slv_ctrl[2];

    // =======================================================
    // edge detection for one-cycle strobes to aes_core
    // same as TRNG start logic
    // =======================================================
    reg ctrl_key_load_d, ctrl_encrypt_d;

    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            ctrl_key_load_d <= 0;
            ctrl_encrypt_d  <= 0;
        end else begin
            ctrl_key_load_d <= ctrl_key_load;
            ctrl_encrypt_d  <= ctrl_encrypt;
        end
    end

    wire key_valid_strobe = (ctrl_key_load && !ctrl_key_load_d); // pulse when key_load goes high
    wire encrypt_start_strobe = (ctrl_encrypt && !ctrl_encrypt_d);   // pulse when encrypt goes high

    // ============== AES Core Signals ==============
    wire            aes_ready;
    wire            aes_busy;
    wire            aes_done;
    wire [127:0]    aes_ciphertext;

    // ---------------------------------------------------
    // done latch
    // aes is a one cycle pulse
    // Must be latched so ARM can read it
    // ----------------------------------------------------
    reg done_latched;

    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            done_latched <= 0;
        end else if (aes_done) begin
            done_latched <= 1; // set when aes signals done
        end else if (ctrl_clear) begin
            done_latched <= 0; // clear when ctrl_clear is set
        end
    end

    // ============= AES Core Instantiation ==============
    aes_core aes_inst (
            .clk           (S_AXI_ACLK),
            .rst_n         (S_AXI_ARESETN),
            .key           ({slv_key[0], slv_key[1], slv_key[2], slv_key[3], slv_key[4], slv_key[5], slv_key[6], slv_key[7]}),
            .key_valid     (key_valid_strobe),
            .plaintext     ({slv_ptext[0], slv_ptext[1], slv_ptext[2], slv_ptext[3]}),
            .encrypt_start (encrypt_start_strobe),
            .clear         (ctrl_clear),
            .ready         (aes_ready),
            .busy          (aes_busy),
            .done          (aes_done),
            .ciphertext    (aes_ciphertext)
    );

    // ============= Status Register =============
    wire [31:0] slv_status = {29'b0, done_latched, aes_busy, aes_ready};

    // ============= AXI Lite Interface =============
    logic axi_awready, axi_wready, axi_bvalid;
    logic axi_arready, axi_rvalid;
    logic [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid;

    // --------- AXI Write Logic ---------
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready  <= 1'b0;
            axi_wready   <= 1'b0;
            axi_bvalid   <= 1'b0;
            slv_ctrl     <= 32'h0;
            slv_key[0]   <= 32'h0; slv_key[1]   <= 32'h0;
            slv_key[2]   <= 32'h0; slv_key[3]   <= 32'h0;
            slv_key[4]   <= 32'h0; slv_key[5]   <= 32'h0;
            slv_key[6]   <= 32'h0; slv_key[7]   <= 32'h0;
            slv_ptext[0] <= 32'h0; slv_ptext[1] <= 32'h0;
            slv_ptext[2] <= 32'h0; slv_ptext[3] <= 32'h0;
        end else begin
            if (axi_awready) axi_awready <= 1'b0;
            if (axi_wready)  axi_wready  <= 1'b0;
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && ~axi_bvalid) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
            end else begin
                axi_awready <= 1'b0;
                axi_wready  <= 1'b0;
            end

            if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID) begin
                case (S_AXI_AWADDR[6:2])
                    ADDR_CTRL:     slv_ctrl      <= S_AXI_WDATA;
                    ADDR_KEY_W0:   slv_key[0]    <= S_AXI_WDATA;
                    ADDR_KEY_W1:   slv_key[1]    <= S_AXI_WDATA;
                    ADDR_KEY_W2:   slv_key[2]    <= S_AXI_WDATA;
                    ADDR_KEY_W3:   slv_key[3]    <= S_AXI_WDATA;
                    ADDR_KEY_W4:   slv_key[4]    <= S_AXI_WDATA;
                    ADDR_KEY_W5:   slv_key[5]    <= S_AXI_WDATA;
                    ADDR_KEY_W6:   slv_key[6]    <= S_AXI_WDATA;
                    ADDR_KEY_W7:   slv_key[7]    <= S_AXI_WDATA;
                    ADDR_PTEXT_W0: slv_ptext[0]  <= S_AXI_WDATA;
                    ADDR_PTEXT_W1: slv_ptext[1]  <= S_AXI_WDATA;
                    ADDR_PTEXT_W2: slv_ptext[2]  <= S_AXI_WDATA;
                    ADDR_PTEXT_W3: slv_ptext[3]  <= S_AXI_WDATA;
                    default: ;  // ciphertext regs are read-only
                endcase
            end

            if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && ~axi_bvalid)
                axi_bvalid <= 1'b1;
            else if (S_AXI_BREADY && axi_bvalid)
                axi_bvalid <= 1'b0;
        end
    end

    // --------- AXI Read Logic ---------
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'h0;
        end else begin
            if (~axi_arready && S_AXI_ARVALID)
                axi_arready <= 1'b1;
            else
                axi_arready <= 1'b0;

            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                case (S_AXI_ARADDR[6:2])
                    ADDR_CTRL:     axi_rdata <= slv_ctrl;
                    ADDR_STATUS:   axi_rdata <= slv_status;
                    ADDR_KEY_W0:   axi_rdata <= slv_key[0];
                    ADDR_KEY_W1:   axi_rdata <= slv_key[1];
                    ADDR_KEY_W2:   axi_rdata <= slv_key[2];
                    ADDR_KEY_W3:   axi_rdata <= slv_key[3];
                    ADDR_KEY_W4:   axi_rdata <= slv_key[4];
                    ADDR_KEY_W5:   axi_rdata <= slv_key[5];
                    ADDR_KEY_W6:   axi_rdata <= slv_key[6];
                    ADDR_KEY_W7:   axi_rdata <= slv_key[7];
                    ADDR_PTEXT_W0: axi_rdata <= slv_ptext[0];
                    ADDR_PTEXT_W1: axi_rdata <= slv_ptext[1];
                    ADDR_PTEXT_W2: axi_rdata <= slv_ptext[2];
                    ADDR_PTEXT_W3: axi_rdata <= slv_ptext[3];
                    ADDR_CTEXT_W0: axi_rdata <= aes_ciphertext[127:96];
                    ADDR_CTEXT_W1: axi_rdata <= aes_ciphertext[95:64];
                    ADDR_CTEXT_W2: axi_rdata <= aes_ciphertext[63:32];
                    ADDR_CTEXT_W3: axi_rdata <= aes_ciphertext[31:0];
                    default:       axi_rdata <= 32'hDEADBEEF;
                endcase
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
                end
        end
    end
endmodule

