`timescale 1ns / 1ps

module hsm_axi_wrapper #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4
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

    // ==== Register Addresses ===
    localparam ADDR_CTRL            = 3'b000;
    localparam ADDR_STATUS          = 3'b001;   // 0x04
    localparam ADDR_DATA_IN         = 3'b010;   // 0x08
    localparam ADDR_DATA_OUT        = 3'b011;   // 0x0C
    localparam ADDR_RAW_OSC         = 3'b100;   // 0x10
    localparam ADDR_COUNTER         = 3'b101;   // 0x14
    localparam ADDR_RAND_OUT        = 3'b110;   // 0x18
    localparam ADDR_SAMP_CNT         = 3'b111;   // 0x1C

    // === Register Map ===
    // R0: Control | R1: status | R2: Data in | R3: data out
    logic [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg_ctrl;
    logic [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg_status;
    logic [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg_data_in;
    logic [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg_data_out;
    logic [C_S_AXI_DATA_WIDTH-1 : 0] slv_reg_counter;

    // TRNG signals
    wire [3:0]  trng_raw_osc;
    wire [31:0] trng_random;
    wire [31:0] trng_sample_count;
    wire        trng_osc_running;

    // Control bit extraction
    wire ctrl_enable    = slv_reg_ctrl[0];
    wire ctrl_sample    = slv_reg_ctrl[1];
    wire ctrl_clear     = slv_reg_ctrl[2];

    // === TRNG inst. ===
    trng_sampler trng_inst (
        .clk            (S_AXI_ACLK),
        .rst_n          (S_AXI_ARESETN),
        .enable         (ctrl_enable),
        .sample_trig    (ctrl_sample),
        .clear          (ctrl_clear),
        .raw_osc        (trng_raw_osc),
        .random_out     (trng_random),
        .sample_count   (trng_sample_count),
        .osc_running    (trng_osc_running)
    );

    // === Free running counter for debug ===
    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN)
            slv_reg_counter <= 32'h0;
        else    
            slv_reg_counter <= slv_reg_counter + 1;
    end

    // === Status register ===
    always_comb begin
        slv_reg_status = 32'h0;
        slv_reg_status[0] = trng_osc_running;
        slv_reg_status[7:4] = trng_raw_osc;
    end

    // --- Internal signals for handshaking ---
    logic axi_awready;
    logic axi_wready;
    logic axi_bvalid;
    logic axi_arready;
    logic axi_rvalid;
    logic [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;

    // Gotta connect logic to output ports
    assign S_AXI_AWREADY    = axi_awready;
    assign S_AXI_WREADY     = axi_wready;
    assign S_AXI_BRESP      = 2'b00;        // OKAY
    assign S_AXI_BVALID     = axi_bvalid;
    assign S_AXI_ARREADY    = axi_arready;
    assign S_AXI_RDATA      = axi_rdata;
    assign S_AXI_RRESP      = 2'b00;        // OKAY
    assign S_AXI_RVALID     = axi_rvalid;

    // === WRITE LOGIC: Ext IP -> Core IP data Tx ===
    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            // reset
            axi_awready <= 0;
            axi_wready  <= 0;
            axi_bvalid  <= 0;
            slv_reg_ctrl    <= 32'h0;
            slv_reg_data_in <= 32'h0;
            slv_reg_data_out<= 32'h0;
        end else begin
            // default case -> deasssert ready signals
            if (axi_awready) axi_awready <= 1'b0;
            if (axi_wready)  axi_wready  <= 1'b0;

            // 1. Wait for Valid Address (AW) and Valid Data (W) ---------------------------
            // Not ready? -> master still presents valid addr/data? -> 
            // Raise our our flags and say i accept...
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && ~axi_bvalid) begin
                axi_awready <= 1;   // address accpted
                axi_wready  <= 1;   // data accepted
            end else begin
                // turn off ready immediately
                axi_awready <= 0;
                axi_wready  <= 0;
            end

            // 2. Actually write the data to the regs -------------------------------------
            // if both sides agree (Rdy=1,valid=1), capture data
            if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID) begin
                // S_AXI_AADDR[3:2] sels. what reg.
                // ignore bits [1:0] axi is 4'B aligned
                case (S_AXI_AWADDR[3:2]) 
                    ADDR_CTRL:     slv_reg_ctrl     <= S_AXI_WDATA;
                    ADDR_DATA_IN:  slv_reg_data_in  <= S_AXI_WDATA;
                    ADDR_DATA_OUT: slv_reg_data_out <= S_AXI_WDATA;
                endcase
            end

            // 3. Send response (BVALID) --------------------------------------------------
            // after we accept, tell external IP we completed the WRITE (BVALID=1)
            if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && ~axi_bvalid) 
                axi_bvalid <= 1;    // raise valid
            else if (S_AXI_BREADY && axi_bvalid)
                axi_bvalid <= 0;    // drop after CPU accepts

        end   
    end

    // === READ LOGIC: Handling Core IP -> External IP data Tx ==================================
    always_ff @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 0;
            axi_rvalid  <= 0;
            axi_rdata   <= 0;
        end else begin
            // 1. Addressing phase -------------------------------------
            // if ext. IP puts a valid addr on the bus (ARVALID), accept it
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1;   // accept addr
                // we latch internally
            end else begin
                axi_arready <= 0;
            end

            // 2. Data phase -------------------------------------------
            // if we accepted an address, must put data on the bus and raise read valid (RVALID)
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1;    // heres your data

                // select which register was addressed
                case (S_AXI_ARADDR[4:2]) 
                    ADDR_CTRL:     axi_rdata <= slv_reg_ctrl;
                    ADDR_STATUS:   axi_rdata <= slv_reg_status;
                    ADDR_DATA_IN:  axi_rdata <= slv_reg_data_in;
                    ADDR_DATA_OUT: axi_rdata <= slv_reg_data_out;
                    ADDR_RAW_OSC:  axi_rdata <= {28'h0, trng_raw_osc};
                    ADDR_COUNTER:  axi_rdata <= slv_reg_counter;
                    ADDR_RAND_OUT: axi_rdata <= trng_random;
                    ADDR_SAMP_CNT: axi_rdata <= trng_sample_count;
                    default:       axi_rdata <= 32'hDEADBEEF;
                endcase
            end else if (axi_rvalid && S_AXI_ARREADY) begin
                // if ext. IP accepted data (RREADY=1) we turn off Read valid (RVALID set to 0)
                axi_rvalid <= 0;
            end
        end
    end
endmodule