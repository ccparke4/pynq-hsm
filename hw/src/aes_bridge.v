`timescale 1ns/1ps
// wrap aes_axi_wrapper.sv for Vivado block design instantiation
module aes_bridge (
    // globals
    input  wire         S_AXI_ACLK,
    input  wire         S_AXI_ARESETN,
    // write addr CH
    input  wire [6:0]   S_AXI_AWADDR,
    input  wire [2:0]   S_AXI_AWPROT,
    input  wire         S_AXI_AWVALID,
    output wire         S_AXI_AWREADY,
    // write data CH
    input  wire [31:0]  S_AXI_WDATA,
    input  wire [3:0]   S_AXI_WSTRB,
    input  wire         S_AXI_WVALID,
    output wire         S_AXI_WREADY,
    // write resp CH
    output wire [1:0]   S_AXI_BRESP,
    output wire         S_AXI_BVALID,
    input  wire         S_AXI_BREADY,
    // read addr CH
    input  wire [6:0]   S_AXI_ARADDR,
    input  wire [2:0]   S_AXI_ARPROT,
    input  wire         S_AXI_ARVALID,
    output wire         S_AXI_ARREADY,
    // read data CH
    output wire [31:0]  S_AXI_RDATA,
    output wire [1:0]   S_AXI_RRESP,
    output wire         S_AXI_RVALID,
    input  wire         S_AXI_RREADY
);
    aes_axi_wrapper #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(7)
    ) inst (
        .S_AXI_ACLK     (S_AXI_ACLK),
        .S_AXI_ARESETN  (S_AXI_ARESETN),
        .S_AXI_AWADDR   (S_AXI_AWADDR),
        .S_AXI_AWPROT   (S_AXI_AWPROT),
        .S_AXI_AWVALID  (S_AXI_AWVALID),
        .S_AXI_AWREADY  (S_AXI_AWREADY),
        .S_AXI_WDATA    (S_AXI_WDATA),
        .S_AXI_WSTRB    (S_AXI_WSTRB),
        .S_AXI_WVALID   (S_AXI_WVALID),
        .S_AXI_WREADY   (S_AXI_WREADY),
        .S_AXI_BRESP    (S_AXI_BRESP),
        .S_AXI_BVALID   (S_AXI_BVALID),
        .S_AXI_BREADY   (S_AXI_BREADY),
        .S_AXI_ARADDR   (S_AXI_ARADDR),
        .S_AXI_ARPROT   (S_AXI_ARPROT),
        .S_AXI_ARVALID  (S_AXI_ARVALID),
        .S_AXI_ARREADY  (S_AXI_ARREADY),
        .S_AXI_RDATA    (S_AXI_RDATA),
        .S_AXI_RRESP    (S_AXI_RRESP),
        .S_AXI_RVALID   (S_AXI_RVALID),
        .S_AXI_RREADY   (S_AXI_RREADY)
    );
endmodule