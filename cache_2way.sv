`timescale 1ns/1ps

module cache_2way #(
    parameter int ADDR_WIDTH = 10,
    parameter int DATA_WIDTH = 8,
    parameter int NUM_SETS   = 8,
    parameter int BLOCK_SIZE = 4,
    parameter int NUM_WAYS   = 2
)(
    input logic clk,
    input logic rst_n,
    input logic                  cpu_req,
    input logic                  cpu_we,
    input logic [ADDR_WIDTH-1:0] cpu_addr,
    input logic [DATA_WIDTH-1:0] cpu_wdata,
    output logic [DATA_WIDTH-1:0] cpu_rdata,
    output logic                  cpu_hit,
    output logic                  cpu_ready
);

    localparam int OFFSET_BITS = $clog2(BLOCK_SIZE); // Bits for word inside block
    localparam int INDEX_BITS  = $clog2(NUM_SETS);   // Bits for selecting set
    localparam int TAG_BITS    = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;

    logic [TAG_BITS-1:0] tag [NUM_SETS][NUM_WAYS]; // Stores tag for each line
    logic valid [NUM_SETS][NUM_WAYS];               // Shows if line has valid data
    logic [DATA_WIDTH-1:0] data [NUM_SETS][NUM_WAYS][BLOCK_SIZE]; // Stores cache data
    logic lru [NUM_SETS];                           // Stores which way is LRU

    logic [TAG_BITS-1:0] cpu_tag;
    logic [INDEX_BITS-1:0] cpu_index;
    logic [OFFSET_BITS-1:0] cpu_offset;

    assign cpu_tag = cpu_addr[ADDR_WIDTH-1 -: TAG_BITS]; // Get tag from address
    assign cpu_index = cpu_addr[OFFSET_BITS +: INDEX_BITS]; // Get set index
    assign cpu_offset = cpu_addr[OFFSET_BITS-1:0]; // Get word offset

    logic hit0, hit1, hit;
    logic hit_way;

    assign hit0 = valid[cpu_index][0] && (tag[cpu_index][0] == cpu_tag); // Check way 0
    assign hit1 = valid[cpu_index][1] && (tag[cpu_index][1] == cpu_tag); // Check way 1
    assign hit = hit0 || hit1; // Hit if either way matches
    assign hit_way = hit0 ? 1'b0 : 1'b1; // Select matching way

    typedef enum logic [1:0] {IDLE, ALLOCATE, FILL_WRITE, DONE} state_t;
    state_t state;

    logic [TAG_BITS-1:0] saved_tag;
    logic [INDEX_BITS-1:0] saved_index;
    logic [OFFSET_BITS-1:0] saved_offset;
    logic saved_we;
    logic [DATA_WIDTH-1:0] saved_wdata;
    logic victim_way;

    logic mem_req;
    logic [ADDR_WIDTH-OFFSET_BITS-1:0] mem_addr;
    logic [BLOCK_SIZE-1:0][DATA_WIDTH-1:0] mem_rdata;
    logic mem_ready;

    localparam int NUM_BLOCKS = 1 << (ADDR_WIDTH - OFFSET_BITS); // Total memory blocks

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cpu_hit <= 1'b0;
            cpu_ready <= 1'b0;
            mem_req <= 1'b0;
            for (int s = 0; s < NUM_SETS; s++) begin
                lru[s] <= 1'b0;
                for (int w = 0; w < NUM_WAYS; w++) begin
                    valid[s][w] <= 1'b0;
                    tag[s][w] <= '0;
                end
            end
        end else begin
            cpu_hit <= 1'b0; // Clear hit signal
            cpu_ready <= 1'b0; // Clear ready signal
            mem_req <= 1'b0; // Clear memory request

            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (hit) begin
                            cpu_hit <= 1'b1; // Request was a hit
                            cpu_ready <= 1'b1; // Request finished

                            if (cpu_we)
                                data[cpu_index][hit_way][cpu_offset] <= cpu_wdata; // Write on hit

                            lru[cpu_index] <= ~hit_way; // Make accessed way MRU
                        end else begin
                            saved_tag <= cpu_tag; // Save requested tag
                            saved_index <= cpu_index; // Save requested set
                            saved_offset <= cpu_offset; // Save requested word
                            saved_we <= cpu_we; // Save read/write operation
                            saved_wdata <= cpu_wdata; // Save write data
                            victim_way <= lru[cpu_index]; // Select LRU way
                            state <= ALLOCATE; // Start loading block
                        end
                    end
                end

                ALLOCATE: begin
                    mem_req <= 1'b1; // Ask memory for block
                    mem_addr <= {saved_tag, saved_index}; // Give memory block address

                    if (mem_ready) begin
                        for (int i = 0; i < BLOCK_SIZE; i++)
                            data[saved_index][victim_way][i] <= mem_rdata[i]; // Copy block to cache

                        tag[saved_index][victim_way] <= saved_tag; // Save new tag
                        valid[saved_index][victim_way] <= 1'b1; // Mark line valid

                        if (saved_we)
                            state <= FILL_WRITE; // Apply original write
                        else
                            state <= DONE; // Finish read miss
                    end
                end

                FILL_WRITE: begin
                    data[saved_index][victim_way][saved_offset] <= saved_wdata; // Write requested data
                    state <= DONE; // Finish request
                end

                DONE: begin
                    cpu_ready <= 1'b1; // Tell CPU request is complete
                    cpu_hit <= 1'b0; // This request was a miss
                    lru[saved_index] <= ~victim_way; // Make new way MRU
                    state <= IDLE; // Wait for next request
                end

                default: state <= IDLE; // Return to idle if needed
            endcase
        end
    end

    always_comb begin
        cpu_rdata = '0; // Default read data

        if (state == IDLE && cpu_req && hit)
            cpu_rdata = data[cpu_index][hit_way][cpu_offset]; // Read hit data
        else if (state == DONE)
            cpu_rdata = data[saved_index][victim_way][saved_offset]; // Read miss data
    end

    logic [DATA_WIDTH-1:0] memory [NUM_BLOCKS][BLOCK_SIZE]; // Main memory storage
    logic busy;
    int delay_count;

    initial begin
        for (int block = 0; block < NUM_BLOCKS; block++)
            for (int word = 0; word < BLOCK_SIZE; word++)
                memory[block][word] = '0; // Start memory with zeros
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; // Memory is not busy
            mem_ready <= 1'b0; // Memory is not ready
            delay_count <= 0; // Clear delay
        end else begin
            mem_ready <= 1'b0; // Ready only for one cycle

            if (!busy && mem_req) begin
                busy <= 1'b1; // Start memory access
                delay_count <= 2; // Wait two cycles
            end else if (busy) begin
                if (delay_count > 1)
                    delay_count <= delay_count - 1; // Reduce delay
                else begin
                    for (int i = 0; i < BLOCK_SIZE; i++)
                        mem_rdata[i] <= memory[mem_addr][i]; // Return complete block

                    mem_ready <= 1'b1; // Tell cache data is ready
                    busy <= 1'b0; // Memory access is finished
                end
            end
        end
    end

endmodule