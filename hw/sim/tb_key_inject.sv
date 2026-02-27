`timescale 1ns/1ps

// =============================================================================
// tb_key_inject.sv - v0.5.0 key injection verif
// Tests the KINJ FSM emulating the TRNG interface with known data.
// Ring oscillators can't produce real entropy in simulation, so to drive
// trng_data/trng_data_vald directly into aes_axi_wrapper
//
// Golden vectors: vectors/kinj_golden.hex (gen'd by gen_kinj_golden.py)
//     line 0 -> expected CT for mock key A + all-zero PT
//     line 1 -> expected CT for mock key B + all-zero PT
// Testing plan
//    1. SW key regression 
//    2. HW key injection - exact KAT against golden CT_A
//    3. key masking - KEY_W0-W7 reads return 0 zreo aftr HW inject
//    4. Key persistence - same key encrypts same PT identically
//    5. Re-injection - exact KAT against golden CT_B
//    6. SW key_load clears key_from_hw flag
// =============================================================================

module tb_key_inject;

    // CLK and RST =======================
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk; // 100MHz

    // AXI signals =======================
    reg [6:0]   awaddr;
    reg         awvalid;
    wire        awready;
    reg [31:0]  wdata;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg [6:0]   araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready; 

    // Mock TRNG Interface ==================
    reg  [31:0] trng_data;
    reg         trng_data_valid;
    wire        trng_ready;

    // DUT inst ==============================
    aes_axi_wrapper #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(7)
    ) dut (
        .S_AXI_ACLK     (clk),
        .S_AXI_ARESETN   (rst_n),
        .S_AXI_AWADDR    (awaddr),
        .S_AXI_AWPROT    (3'b000),
        .S_AXI_AWVALID   (awvalid),
        .S_AXI_AWREADY   (awready),
        .S_AXI_WDATA     (wdata),
        .S_AXI_WSTRB     (4'hF),
        .S_AXI_WVALID    (wvalid),
        .S_AXI_WREADY    (wready),
        .S_AXI_BRESP     (bresp),
        .S_AXI_BVALID    (bvalid),
        .S_AXI_BREADY    (bready),
        .S_AXI_ARADDR    (araddr),
        .S_AXI_ARPROT    (3'b000),
        .S_AXI_ARVALID   (arvalid),
        .S_AXI_ARREADY   (arready),
        .S_AXI_RDATA     (rdata),
        .S_AXI_RRESP     (rresp),
        .S_AXI_RVALID    (rvalid),
        .S_AXI_RREADY    (rready),
        // MOCK TRNG interface
        .trng_data        (trng_data),
        .trng_data_valid  (trng_data_valid),
        .trng_req         (trng_req)
    );

    // AXI Register addresses ========================
    localparam CTRL      = 7'h00;
    localparam STATUS    = 7'h04;
    localparam KEY_W0    = 7'h10;
    localparam KEY_W1    = 7'h14;
    localparam KEY_W2    = 7'h18;
    localparam KEY_W3    = 7'h1C;
    localparam KEY_W4    = 7'h20;
    localparam KEY_W5    = 7'h24;
    localparam KEY_W6    = 7'h28;
    localparam KEY_W7    = 7'h2C;
    localparam PTEXT_W0  = 7'h30;
    localparam PTEXT_W1  = 7'h34;
    localparam PTEXT_W2  = 7'h38;
    localparam PTEXT_W3  = 7'h3C;
    localparam CTEXT_W0  = 7'h40;
    localparam CTEXT_W1  = 7'h44;
    localparam CTEXT_W2  = 7'h48;
    localparam CTEXT_W3  = 7'h4C;

    // Golden Vectors (from gen_kinj_golden.py) ========================
    reg [127:0] golden_ct [0:1];    // [0] key A, [1] key b

    initial begin
        $readmemh("vectors/kinj_golden.hex", golden_ct);
    end

    // Mock TRNG data  ========================
    // 2 sets of 8 known words (TRNG out)
    reg  [31:0] mock_key_a [0:7];
    reg  [31:0] mock_key_b [0:7];

    // NIST FIPS 197 C.3 key for SW regression
    reg [31:0] nist_key [0:7];

    // AXI Write Task ========================
    task axi_write(input [6:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            awaddr  <= addr;
            awvalid <= 1;
            wdata   <= data;
            wvalid  <= 1;
            bready  <= 1;
            wait (awready && wready);
            @(posedge clk);
            awvalid <= 0;
            wvalid <= 0;
            wait (bvalid);
            @(posedge clk);
            bready <= 0;
        end
    endtask

    // AXI Read Task ========================
    reg  [31:0] read_result;
    task axi_read(input [6:0] addr);
        begin
            @(posedge clk);
            araddr  <= addr;
            arvalid <= 1;
            rready  <= 1;
            wait (arready);
            @(posedge clk);
            arvalid <= 0;
            wait (rvalid);
            read_result <= rdata;
            @(posedge clk);
            rready <= 0;
        end
    endtask

    // PPoll status until bit is set ========================
    task poll_status(input integer bit_pos, input integer timeout_cycles);
        integer i;
        begin
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                axi_read(STATUS);
                if (read_result[bit_pos])
                    return; // bit is set, exit task
            end
            $display("ERROR: Timeout polling status bit %0d", bit_pos);
            fail_count = fail_count + 1;
        end
    endtask

    // SW Key Load & Encrypt Task ========================
    reg  [127:0] ct_result;
    task sw_encrypt(
        input [31:0] k0, k1, k2, k3, k4, k5, k6, k7,
        input [31:0] p0, p1, p2, p3
    )
        begin
            axi_write(KEY_W0, k0); 
            axi_write(KEY_W1, k1);
            axi_write(KEY_W2, k2);
            axi_write(KEY_W3, k3);
            axi_write(KEY_W4, k4);
            axi_write(KEY_W5, k5);
            axi_write(KEY_W6, k6);
            axi_write(KEY_W7, k7);
            axi_write(CTRL, 32'h1); // start encryption
            axi_write(CTRL, 32'h0); // clear start bit
            poll_status(0, 200);
            axi_write(PTEXT_W0, p0);
            axi_write(PTEXT_W1, p1);
            axi_write(PTEXT_W2, p2);
            axi_write(PTEXT_W3, p3);
            axi_write(CTRL, 32'h2); // start decryption
            axi_write(CTRL, 32'h0); // clear start bit
            poll_status(2, 200);
            axi_read(CTEXT_W0);
            ct_result[127:96] <= read_result;
            axi_read(CTEXT_W1);
            ct_result[95:64] <= read_result;
            axi_read(CTEXT_W2);
            ct_result[63:32] <= read_result;
            axi_read(CTEXT_W3);
            ct_result[31:0] <= read_result;
            axi_write(CTRL, 32'h4); // clear status bits
            axi_write(CTRL, 32'h0); // clear start bit
        end
    endtask

    // HW Key Injection Task ========================
    task hw_inject_encrypt(input [31:0] p0, p1, p2, p3);
        begin
            axi_write(CTRL, 32'h8); // trigger HW key inject
            axi_write(CTRL, 32'h0); // clear start bit
            poll_status(0, 2000);   // wait for key expansion
            axi_write(PTEXT_W0, p0);
            axi_write(PTEXT_W1, p1);
            axi_write(PTEXT_W2, p2);
            axi_write(PTEXT_W3, p3);
            axi_write(CTRL, 32'h2); // start decryption
            axi_write(CTRL, 32'h0); // clear start bit
            poll_status(2, 200);
            axi_read(CTEXT_W0);
            ct_result[127:96] <= read_result;
            axi_read(CTEXT_W1);
            ct_result[95:64] <= read_result;
            axi_read(CTEXT_W2);
            ct_result[63:32] <= read_result;
            axi_read(CTEXT_W3);
            ct_result[31:0] <= read_result;
            axi_write(CTRL, 32'h4); // clear status bits
            axi_write(CTRL, 32'h0); // clear start bit
        end
    endtask

    // Mock TRNG resp ==========================================
    // watches trng_req, responds w/ mock data after delay
    integer trng_word_idx = 0;
    reg     inject_set = 0;     // 0 = key A, 1 = key B

    always @(posedge clk) begin
        if (!rst_n) begin
            trng_data <='0;
            trng_data_valid <= 0;
            trng_word_idx <= 0;
        end else begin
            trng_data_valid <= 0;

            if (trng_req) begin
                // simulate TRNG collection latency ~20 cycles
                repeat(20) @(posedge clk);
                if (inject_set == 0) begin
                    trng_data <= mock_key_a[trng_word_idx];
                end else begin
                    trng_data <= mock_key_b[trng_word_idx];
                end
                trng_data_valid <= 1;
                @(posedge clk);
                trng_data_valid <= 0;
                trng_word_idx <= (trng_word_idx + 1) % 8;
            end
        end
    end

    // Test checker ==========================================
    task check(input string name, input logic condition) 
        begin
            test_num = test_num + 1;
            if (condition) begin
                $display("   [PASS] Test %0d: %d", test_num, name);
                pass_count = pass_count + 1;
            end else begin
                $display("   [FAIL] Test %0d: %d", test_num, name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Test Sequence ==========================================
    reg [127:0] ct_inject_a;
    reg [127:0] ct_persist;
    reg [127:0] ct_inject_b;

    initial begin
        $display("");
        $display("=========================================");
        $display("Starting Key Injection Testbench");
        $display("=========================================");

        // init ----------
        awvalid = 0;
        wvalid  = 0;
        bready  = 0;
        arvalid = 0;
        rready  = 0;
        trng_data = 0;
        trng_data_valid = 0;

        // Mock key A - deterministic ~random~ vals
        mock_key_a[0] = 32'hDEADBEEF;
        mock_key_a[1] = 32'hCAFEBABE;
        mock_key_a[2] = 32'h12345678;
        mock_key_a[3] = 32'h9ABCDEF0;
        mock_key_a[4] = 32'hFEDCBA98;
        mock_key_a[5] = 32'h76543210;
        mock_key_a[6] = 32'hAAAA5555;
        mock_key_a[7] = 32'h0F0FF0F0;

        // Mock key B - different deterministic vals
        mock_key_b[0] = 32'h11111111;
        mock_key_b[1] = 32'h22222222;
        mock_key_b[2] = 32'h33333333;
        mock_key_b[3] = 32'h44444444;
        mock_key_b[4] = 32'h55555555;
        mock_key_b[5] = 32'h66666666;
        mock_key_b[6] = 32'h77777777;
        mock_key_b[7] = 32'h88888888;

        // NIST FIPS 197 C.3 key for SW regression
        nist_key[0] = 32'h00010203;
        nist_key[1] = 32'h04050607;
        nist_key[2] = 32'h08090a0b;
        nist_key[3] = 32'h0c0d0e0f;
        nist_key[4] = 32'h10111213;
        nist_key[5] = 32'h14151617;
        nist_key[6] = 32'h18191a1b;
        nist_key[7] = 32'h1c1d1e1f;

        // reset ----------
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // TEST 1 - SW key regression ============================
        $disply("");
        $display("--- Test 1: SW Key Regression - NIST FIPS 197 C.3 Vector ---");
        sw_encrypt(
            nist_key[0], nist_key[1], nist_key[2], nist_key[3],
            nist_key[4], nist_key[5], nist_key[6], nist_key[7],
            32'h00112233, 32'h44556677, 32'h8899aabb, 32'hccddeeff
        );
        $display(" CT:%08h_%08h_%08h_%08h", ct_result[127:96], ct_result[95:64], ct_result[63:32], ct_result[31:0]);
        check("NIST C.3 ciphertext matches", ct_result == 128'h8ea2b7ca_516745bf_eafc4990_4b496089);

        // verify key_from_hw is 0 after SW load
        axi_read(STATUS);
        check("key_from_hw is 0 after SW load", read_result[3] == 0);

        // TEST 2 - HW Key Injection KAT ============================
        $display("");
        $display("----- Test 2: HW Key Injection (Key A) -----");
        inject_set = 0;
        trng_word_idx = 0;
        hw_inject_encrypt(32'h0, 32'h0, 32'h0, 32'h0);
        ct_inject_a = ct_result;
        $display("  CT:     %08h_%08h_%08h_%08h", ct_result[127:96], ct_result[95:64], ct_result[63:32], ct_result[31:0]);
        $display("  Golden: %08h_%08h_%08h_%08h", golden_ct[0][127:96], golden_ct[0][95:64], golden_ct[0][63:32], golden_ct[0][31:0]);
        check("Key A ciphertext matches golden", ct_result == golden_ct[0]);

        // Verify status bits
        axi_read(STATUS);
        check("key_from_hw=1 after HW injection", read_result[3] == 1);
        check("kinj_busy=0 after injection complete", read_result[4] == 0);


        // TEST 3 - Key Masking ============================
        $display("");
        $display("----- Test 3: Key Masking -----");
        begin
            reg all_zero;
            integer i;
            all_zero = 1;
            for (i = 0; i < 8; i = i + 1) begin
                axi_read(KEY_W0 + (i * 4));
                $display("  KEY_W%0d read: 0x%08h", i, read_result);
                if (read_result != 32'h0)
                    all_zero = 0;
            end
            check("All KEY_Wn reads return 0x00000000", all_zero);
            
        end

        // TEST 4 - Key Persistence ============================
        $display("");
        $display("----- Test 4: Key Persistence -----");
        axi_write(PTEXT_W0, 32'h0); axi_write(PTEXT_W1, 32'h0);
        axi_write(PTEXT_W2, 32'h0); axi_write(PTEXT_W3, 32'h0);
        axi_write(CTRL, 32'h2);
        axi_write(CTRL, 32'h0);
        poll_status(2, 200);
        axi_read(CTEXT_W0); ct_persist[127:96] = read_result;
        axi_read(CTEXT_W1); ct_persist[95:64]  = read_result;
        axi_read(CTEXT_W2); ct_persist[63:32]  = read_result;
        axi_read(CTEXT_W3); ct_persist[31:0]   = read_result;
        axi_write(CTRL, 32'h4);
        axi_write(CTRL, 32'h0);
        display("  CT: %08h_%08h_%08h_%08h", ct_persist[127:96], ct_persist[95:64], ct_persist[63:32], ct_persist[31:0]);
        check("Same key produces same ciphertext", ct_persist == ct_inject_a);

        // TEST 5 - Re-injection with Key B ============================
        $display("");
        $display("----- Test 5: Re-injection (Key B) -----");
        inject_set = 1;
        trng_word_idx = 0;
        hw_inject_encrypt(32'h0, 32'h0, 32'h0, 32'h0);
        ct_inject_b = ct_result;
        display("  CT:     %08h_%08h_%08h_%08h", ct_result[127:96], ct_result[95:64], ct_result[63:32], ct_result[31:0]);
        $display("  Golden: %08h_%08h_%08h_%08h", golden_ct[1][127:96], golden_ct[1][95:64], golden_ct[1][63:32], golden_ct[1][31:0]);
        check("Key B ciphertext matches golden", ct_result == golden_ct[1]);
        check("Key B CT differs from Key A CT", ct_inject_b != ct_inject_a);

        // TEST 6 - SW key load clears key_from_hw flag ============================
        $display("");
        $display("----- Test 6: SW key_load clears key_from_hw -----");
        axi_read(STATUS);
        check("key_from_hw=1 before SW key load", read_result[3] == 1);

        axi_write(KEY_W0, nist_key[0]);
        axi_write(CTRL, 32'h1);
        axi_write(CTRL, 32'h0);
        poll_status(0, 200);

        axi_read(STATUS);
        check("key_from_hw=0 after SW key load", read_result[3] == 0);

        axi_read(KEY_W0);
        check("KEY_W0 readable after SW key load", read_result == nist_key[0]);

        // Summary ==========================================
        $display("");
        $display("=================================================");
        $display(" Key Injection Test Summary");
        $display("   PASSED: %0d", pass_count);
        $display("   FAILED: %0d", fail_count);
        $display("=================================================");
        if (fail_count == 0)
            $display(" ALL TESTS PASSED");
        else
        $display(" *** FAILURES DETECTED ***");
        $display("");
        $finish;
    end

    // Timeout watchdog - if simulation runs too long, something is wrong
    initial begin
        #500_000;  // 500us
        $display("ERROR: Global timeout — simulation stuck!");
        $finish;
    end


endmodule
