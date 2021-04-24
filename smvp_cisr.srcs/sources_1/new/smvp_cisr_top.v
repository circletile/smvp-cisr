`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2021 05:58:28 PM
// Design Name: 
// Module Name: smvp_cisr_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module smvp_cisr_top
    // If you need to edit these, use Find/Replace to make sure ALL modules are updated
    #(parameter SM_DATA_INPUT_LENGTH=12, // Sparse Matrix data (values) length measured in bits. Derived from BRAM data structures
      parameter SM_DATA_OUITPUT_LENGTH=12, // Data output length measired in bits. Derived from BRAM data structures
      parameter SM_VECTOR_INPUT_LENGTH=1, // Vector input length measured in bits. Derived from decision to use input vector of all ones for design simplificartion.
      parameter SM_CHANNEL_COUNT=6, // Number of CISR channels
      parameter SM_FIFO_QUEUE_DEPTH=32 // Queue depth for all FIFOs. Value determined experimentally, with a suggested value of 0.25x-0.5x of CISR data row count.
    )
    (
    // Basys3 Clock Input (defined in constraints)
    input clk,
    
    // Basys3 Button Inputs (defined in constraints)
    input btnC,
    input btnL,
    input btnR,

    // Basys3 7seg LEDs
    output [6:0] seg,
    output [0:0] dp,
    output [3:0] an
    );
    
    // BRAM I/O
    reg [14:0] bram_addr;
    wire [35:0] bram_dout;
    
    wire [SM_DATA_OUITPUT_LENGTH-1:0] fifo_test_input;
    wire [SM_DATA_OUITPUT_LENGTH-1:0] fifo_test_output;
    wire [4:0] fifo_test_flags;
    reg fifo_test_write_en, fifo_test_read_en;
    
    
    // Button Utility Vars
    wire stable_btnC;
    wire [1:0] dummy_btnC;
    
    // Debounce all the things (buttons)
    PushButton_Debouncer db_btnC (.clk(clk), .PB(btnC), .PB_state(stable_btnC), .PB_down(dummy_btnC[0]), .PB_up(dummy_btnC[1]));
    
    blk_mem_gen_0 cisr_bram (.clka(clk), .addra(bram_addr), .douta(bram_dout));
    cisr_fifo test_fifo (.clk(clk), .reset(stable_btnC),
                         .write_en(fifo_test_write_en), .read_en(fifo_test_read_en), 
                         .data_in(fifo_test_input), .data_out(fifo_test_output),
                         .fifo_full_out(fifo_test_flags[4]), .fifo_empty_out(fifo_test_flags[3]), .fifo_low_water_out(fifo_test_flags[2]), .fifo_overflow_out(fifo_test_flags[1]), .fifo_underflow_out(fifo_test_flags[0]));
    
    initial begin
        bram_addr = 4'h0;   // Range: 'h0000 to '7FFF
        fifo_test_write_en = 0;
        fifo_test_read_en = 0;
    end
    
    assign fifo_test_input = bram_dout[32:20];
    
    always @(posedge clk) begin
        case (bram_addr)
            'h7FFF: bram_addr <= 'h7FFF;
            default: bram_addr <= bram_addr + 1;
        endcase      
        
        fifo_test_write_en <= 1;
        fifo_test_read_en <= 1;
          
    end
    
endmodule


// Module: CISR Processing Element - Multiplier
module cisr_pe_mult     
    #(parameter SM_DATA_INPUT_LENGTH=1)
    (input clk, reset, input [SM_DATA_INPUT_LENGTH-1:0] value_in, input [SM_DATA_INPUT_LENGTH-1:0] vector_in, output reg [SM_DATA_INPUT_LENGTH-1:0] product_out);
    
    initial begin
        product_out = 0;
    end
    
    always @(posedge clk) begin
        if (reset) begin
            product_out = 0;
        end
        else product_out <= value_in * vector_in;
    end
endmodule

// Module: CISR I/O Element - FIFO
// ref: https://www.fpga4student.com/2017/01/verilog-code-for-fifo-memory.html
module cisr_fifo
    #(parameter SM_DATA_OUITPUT_LENGTH=12, SM_FIFO_QUEUE_DEPTH=32)
    (input clk, reset, write_en, read_en,
     input [SM_DATA_OUITPUT_LENGTH-1:0] data_in, output [SM_DATA_OUITPUT_LENGTH-1:0] data_out, // Using SM_DATA_OUITPUT_LENGTH here since it represents the largest value we may need to use a FIFO for
     output fifo_full_out, fifo_empty_out, fifo_low_water_out, fifo_overflow_out, fifo_underflow_out);
     
     //
     // Read I/O Section
     //
     reg [4:0] read_ptr;
     wire fifo_read_flag;
     reg fifo_empty_flag;
     
     initial begin
        fifo_empty_flag = 0;
        read_ptr = 0;
     end
     
     // Determine if read request can be performed safely
     assign fifo_read_flag = (~fifo_empty_flag) & read_en;
     
     // Manage memory location read pointer
     always @(posedge clk or negedge reset) begin
        if(~reset) read_ptr <= 5'b000000;  
        else if(fifo_read_flag) read_ptr <= read_ptr + 5'b000001;  
        else read_ptr <= read_ptr;   
     end
     
     //
     // Write I/O Section
     //
     reg [4:0] write_ptr;
     wire fifo_write_flag;
     reg fifo_full_flag;
     
     initial begin
        fifo_full_flag = 0;
        write_ptr = 0;
     end
     
     // Determine if write request can be performed safely
     assign fifo_write_flag = (~fifo_full_flag) & write_en;
     
     // Manage memory location write pointer
     always @(posedge clk or negedge reset) begin  
        if(~reset) write_ptr <= 5'b000000;  
        else if(fifo_write_flag) write_ptr <= write_ptr + 5'b000001;  
        else write_ptr <= write_ptr;  
     end
     
     //
     // Internal Memory Section
     //
     reg [SM_DATA_OUITPUT_LENGTH-1:0] int_data_out, int_data_in;
     reg [SM_DATA_OUITPUT_LENGTH-1:0] fifo_memory [SM_FIFO_QUEUE_DEPTH-1:0];
     integer i; // for initializing fifo memory
     
     initial begin
        int_data_out = 0;
        int_data_in = 0;
        for( i = 0; i < SM_DATA_OUITPUT_LENGTH; i = i + 1) begin
            fifo_memory[i] = 0;
        end
     end
     
     // Perform FIFO memory write operations if safe
     always @(posedge clk) begin
        if ( fifo_write_flag ) fifo_memory[write_ptr[3:0]] <= data_in;
     end
     
     // Perform FIFO memory read operation
     assign data_out = fifo_memory[read_ptr[3:0]];
     
     //
     // Status I/O Section
     //
     wire ptr_full_bit_comp, pointer_equal;
     wire[4:0] pointer_result;
     reg overflow_flag, underflow_flag, low_water_flag;
     
     initial begin
        overflow_flag = 0;
        underflow_flag = 0;
        low_water_flag = 0;
     end
     
     // Generate internal status flags
     assign ptr_full_bit_comp = write_ptr[4] ^ read_ptr[4];  
     assign pointer_equal = (write_ptr[3:0] - read_ptr[3:0]) ? 0:1;  
     assign pointer_result = write_ptr[4:0] - read_ptr[4:0];  
     
     // Assign status flags to FIFO module outputs
     assign fifo_overflow_out = fifo_full_flag & write_en;  
     assign fifo_underflow_out = fifo_empty_flag & read_en;  
     assign fifo_low_water_out = low_water_flag;
     
     // Evaluate for FIFO full, empty, or "low water threshold" states
     always @(*) begin  
        fifo_full_flag = ptr_full_bit_comp & pointer_equal;  
        fifo_empty_flag = (~ptr_full_bit_comp) & pointer_equal;  
        low_water_flag = (pointer_result[4] || pointer_result[3]) ? 1:0;  
     end  
     
     // Evaluare for FIFO overflow condition
     always @(posedge clk or negedge reset) begin  
        if(~reset) overflow_flag <= 0;  
        else if((overflow_flag == 1 ) && (fifo_read_flag == 0)) overflow_flag <= 1;  
        else if(fifo_read_flag) overflow_flag <= 0;  
        else overflow_flag <= overflow_flag;  
     end  
     
     // Evaluate for FIFO underflow condition
     always @(posedge clk or negedge reset) begin  
        if(~reset) underflow_flag <= 0;  
        else if((underflow_flag == 1 ) && (fifo_write_flag == 0)) underflow_flag <= 1;  
        else if(fifo_write_flag) underflow_flag <= 0;  
        else underflow_flag <= underflow_flag;  
     end  

endmodule

// Module: Button Debounce
// ref: https://www.fpga4fun.com/Debouncer2.html
module PushButton_Debouncer(
    input clk,
    input PB,  // "PB" is the glitchy, asynchronous to clk, active low push-button signal

    // from which we make three outputs, all synchronous to the clock
    output reg PB_state,  // 1 as long as the push-button is active (down)
    output PB_down,  // 1 for one clock cycle when the push-button goes down (i.e. just pushed)
    output PB_up   // 1 for one clock cycle when the push-button goes up (i.e. just released)
    );

    // First use two flip-flops to synchronize the PB signal the "clk" clock domain
    reg PB_sync_0;  always @(posedge clk) PB_sync_0 <= ~PB;  // invert PB to make PB_sync_0 active high
    reg PB_sync_1;  always @(posedge clk) PB_sync_1 <= PB_sync_0;

    // Next declare a 16-bits counter
    reg [15:0] PB_cnt;

    // When the push-button is pushed or released, we increment the counter
    // The counter has to be maxed out before we decide that the push-button state has changed!
    wire PB_idle = (PB_state==PB_sync_1);
    wire PB_cnt_max = &PB_cnt;	// true when all bits of PB_cnt are 1's
    
    always @(posedge clk)
        if(PB_idle)
        PB_cnt <= 0;  // nothing's going on
        else begin
            PB_cnt <= PB_cnt + 16'd1;  // something's going on, increment the counter
            if(PB_cnt_max) PB_state <= ~PB_state;  // if the counter is maxed out, PB changed!
        end

        assign PB_down = ~PB_idle & PB_cnt_max & ~PB_state;
        assign PB_up   = ~PB_idle & PB_cnt_max &  PB_state;
endmodule