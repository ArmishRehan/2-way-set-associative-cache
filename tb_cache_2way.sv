`timescale 1ns/1ps

module tb_cache_2way;

    // ========================================================
    // Parameters
    // ========================================================

    localparam int ADDR_WIDTH = 10;
    localparam int DATA_WIDTH = 8;
    localparam int NUM_SETS   = 8;
    localparam int BLOCK_SIZE = 4;


    // ========================================================
    // Clock and Reset
    // ========================================================

    logic clk = 0;
    logic rst_n;


    // ========================================================
    // CPU Signals
    // ========================================================

    logic                  cpu_req;
    logic                  cpu_we;
    logic [ADDR_WIDTH-1:0] cpu_addr;
    logic [DATA_WIDTH-1:0] cpu_wdata;

    logic [DATA_WIDTH-1:0] cpu_rdata;
    logic                  cpu_hit;
    logic                  cpu_ready;


    // ========================================================
    // Clock
    // ========================================================

    always #5 clk = ~clk;


    // ========================================================
    // Cache Design
    //
    // Memory is already inside cache_2way
    // ========================================================

    cache_2way #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_SETS(NUM_SETS),
        .BLOCK_SIZE(BLOCK_SIZE),
        .NUM_WAYS(2)
    ) dut (

        .clk       (clk),
        .rst_n     (rst_n),

        .cpu_req   (cpu_req),
        .cpu_we    (cpu_we),
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_wdata),

        .cpu_rdata (cpu_rdata),
        .cpu_hit   (cpu_hit),
        .cpu_ready (cpu_ready)

    );


    // ========================================================
    // Test Counters
    // ========================================================

    int errors = 0;
    int checks = 0;


    // ========================================================
    // Task: Send CPU Request
    // ========================================================

    task automatic do_req(

        input logic [ADDR_WIDTH-1:0] addr,
        input logic                  we,
        input logic [DATA_WIDTH-1:0] wdata,

        output logic [DATA_WIDTH-1:0] rdata,
        output logic                  hit

    );

        begin

            // Start request
            @(negedge clk);

            cpu_req   = 1'b1;
            cpu_we    = we;
            cpu_addr  = addr;
            cpu_wdata = wdata;


            // Wait for request to complete
            do begin

                @(negedge clk);

            end while (!cpu_ready);


            // Get results
            rdata = cpu_rdata;
            hit   = cpu_hit;


            // Stop request
            cpu_req = 1'b0;

        end

    endtask


    // ========================================================
    // Task: Write Test
    // ========================================================

    task automatic check_write(

        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] wdata

    );

        logic [DATA_WIDTH-1:0] rd;
        logic hit;

        begin

            do_req(
                addr,
                1'b1,
                wdata,
                rd,
                hit
            );


            $display(
                "[%0t] WRITE addr=%0d data=%0h hit=%0b",
                $time,
                addr,
                wdata,
                hit
            );

        end

    endtask


    // ========================================================
    // Task: Read Test
    // ========================================================

    task automatic check_read(

        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] expected,
        input logic                  expected_hit,
        input string                 label

    );

        logic [DATA_WIDTH-1:0] rd;
        logic hit;

        begin

            do_req(
                addr,
                1'b0,
                '0,
                rd,
                hit
            );


            checks++;


            $display(
                "[%0t] READ addr=%0d data=%0h hit=%0b (%s)",
                $time,
                addr,
                rd,
                hit,
                label
            );


            // Check data
            if (rd !== expected) begin

                $display(
                    "ERROR: Expected data=%0h, Got=%0h",
                    expected,
                    rd
                );

                errors++;

            end


            // Check hit
            if (hit !== expected_hit) begin

                $display(
                    "ERROR: Expected hit=%0b, Got=%0b",
                    expected_hit,
                    hit
                );

                errors++;

            end

        end

    endtask


    // ========================================================
    // Address Parameters
    //
    // All three addresses use SET 3.
    //
    // A -> Tag 5
    // B -> Tag 9
    // C -> Tag 13
    //
    // Since cache has 2 ways:
    //
    // A + B -> Both fit
    //
    // A + B + C -> One must be replaced
    // ========================================================

    localparam logic [ADDR_WIDTH-1:0] ADDR_A =
        (5 << 5) | (3 << 2);

    localparam logic [ADDR_WIDTH-1:0] ADDR_B =
        (9 << 5) | (3 << 2);

    localparam logic [ADDR_WIDTH-1:0] ADDR_C =
        (13 << 5) | (3 << 2);


    // ========================================================
    // Test Sequence
    // ========================================================

    initial begin


        // ----------------------------------------------------
        // Initialize
        // ----------------------------------------------------

        rst_n     = 1'b0;

        cpu_req   = 1'b0;
        cpu_we    = 1'b0;
        cpu_addr  = '0;
        cpu_wdata = '0;


        // ----------------------------------------------------
        // Reset
        // ----------------------------------------------------

        repeat (3) @(negedge clk);

        rst_n = 1'b1;


        // ====================================================
        // TEST 1
        // Write A
        //
        // Expected:
        // MISS -> Load block -> Write AA
        // ====================================================

        $display(
            "\n=== TEST 1: Write A ==="
        );

        check_write(
            ADDR_A,
            8'hAA
        );


        // ====================================================
        // TEST 2
        // Read A
        //
        // Expected:
        // HIT
        // Data = AA
        // ====================================================

        $display(
            "\n=== TEST 2: Read A ==="
        );

        check_read(
            ADDR_A,
            8'hAA,
            1'b1,
            "A should HIT"
        );


        // ====================================================
        // TEST 3
        // Write B
        //
        // B has same SET but different TAG.
        //
        // Expected:
        // MISS -> Use other way
        // ====================================================

        $display(
            "\n=== TEST 3: Write B ==="
        );

        check_write(
            ADDR_B,
            8'hBB
        );


        // ====================================================
        // TEST 4
        // Read A and B
        //
        // Expected:
        // Both HIT
        // ====================================================

        $display(
            "\n=== TEST 4: Read A and B ==="
        );

        check_read(
            ADDR_A,
            8'hAA,
            1'b1,
            "A should HIT"
        );

        check_read(
            ADDR_B,
            8'hBB,
            1'b1,
            "B should HIT"
        );


        // ====================================================
        // TEST 5
        // Write C
        //
        // C has same SET.
        //
        // Cache already has A and B.
        // One must be replaced using LRU.
        // ====================================================

        $display(
            "\n=== TEST 5: Write C - LRU Replacement ==="
        );

        check_write(
            ADDR_C,
            8'hCC
        );


        // ====================================================
        // TEST 6
        // Read C
        //
        // Expected:
        // HIT
        // Data = CC
        // ====================================================

        $display(
            "\n=== TEST 6: Read C ==="
        );

        check_read(
            ADDR_C,
            8'hCC,
            1'b1,
            "C should HIT"
        );


        // ====================================================
        // TEST 7
        // Read B
        //
        // B should still be in cache.
        // ====================================================

        $display(
            "\n=== TEST 7: Read B ==="
        );

        check_read(
            ADDR_B,
            8'hBB,
            1'b1,
            "B should HIT"
        );


        // ====================================================
        // TEST 8
        // Read A
        //
        // A was the LRU block.
        // C replaced A.
        //
        // Expected:
        // MISS
        //
        // Memory originally contains 00.
        // Since there is no write-back,
        // A's AA value was not saved to memory.
        // ====================================================

        $display(
            "\n=== TEST 8: Read A Again ==="
        );

        check_read(
            ADDR_A,
            8'h00,
            1'b0,
            "A should MISS after LRU replacement"
        );


        // ====================================================
        // SUMMARY
        // ====================================================

        $display(
            "\n========================================"
        );

        $display(
            "           TEST SUMMARY"
        );

        $display(
            "========================================"
        );

        $display(
            "Checks : %0d",
            checks
        );

        $display(
            "Errors : %0d",
            errors
        );


        if (errors == 0) begin

            $display(
                "RESULT: ALL TESTS PASSED"
            );

        end

        else begin

            $display(
                "RESULT: %0d TEST(S) FAILED",
                errors
            );

        end


        $display(
            "========================================\n"
        );


        $finish;

    end

endmodule