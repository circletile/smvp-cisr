`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: University of Central Florida
// Engineer: Chris Upchurch
// 
// Create Date: 04/24/2021 11:01:46 AM
// Design Name: CISR SMVP Accelerator
// Module Name: smvp_cisr_top
// Project Name: CDA5110 Final Project - Optional Objective
// Target Devices: Digilent Basys3 (Artix-7 XC7A35T-1CPG236C)
// Tool Versions: Vivado 2020.2
// Description: Proof of concept for an CISR SmVP accelerator implemented as parallel queues and systolic array accumulators.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: Implementation is currenmtly incomplete, but has the major functional elements/modules implemented.
// 
//////////////////////////////////////////////////////////////////////////////////



module smvp_cisr_top
    // If you need to edit these, use Find/Replace to make sure ALL modules are updated
    #(parameter SM_DATA_INPUT_LENGTH=12, // Sparse Matrix data (values) length measured in bits. Derived from BRAM data structures
      parameter SM_DATA_OUTPUT_LENGTH=12, // Data output length measired in bits. Derived from BRAM data structures
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
    wire [3:0] bram_control_val;
    wire [11:0] bram_value_val, bram_value_colind, bram_rowlen_val;
    wire [7:0] bram_value_slot;
    wire [4:0] bram_rowlen_valid;
    
    // Channel I/O
    reg bram_data_end_flag, bram_data_start_flag; 
    
    reg [SM_DATA_OUTPUT_LENGTH-1:0] channel_value_in [SM_CHANNEL_COUNT-1:0];
    reg [SM_DATA_OUTPUT_LENGTH-1:0] channel_col_ind_in [SM_CHANNEL_COUNT-1:0];
    reg [SM_DATA_OUTPUT_LENGTH-1:0] channel_row_len_in [SM_CHANNEL_COUNT-1:0];
    
    wire [SM_DATA_OUTPUT_LENGTH-1:0] channel_value_out [SM_CHANNEL_COUNT-1:0];
    wire [SM_DATA_OUTPUT_LENGTH-1:0] channel_rowid_out [SM_CHANNEL_COUNT-1:0];
    
    wire [SM_DATA_OUTPUT_LENGTH-1:0] channel_rowid_in [SM_CHANNEL_COUNT-1:0];
    wire [SM_DATA_OUTPUT_LENGTH-1:0] channel_rowlen_out [SM_CHANNEL_COUNT-1:0];
    
    wire [SM_DATA_OUTPUT_LENGTH-1:0] vecbuf_vector_in [SM_CHANNEL_COUNT-1:0];
    wire [SM_DATA_OUTPUT_LENGTH-1:0] channel_colind_out [SM_CHANNEL_COUNT-1:0];
    
    reg [SM_CHANNEL_COUNT-1:0] fifo_rowlen_read_en;
    
    wire [SM_CHANNEL_COUNT-1:0] decoder_rowid_dataempty, vecbuf_vector_dataempty, channel_rowlen_dataempty, channel_colind_dataempty,
                                channel_value_dataempty, channel_rowid_dataempty;
    
    // Button Utility Vars
    wire stable_btnC;
    wire [1:0] dummy_btnC; // for attaching unused debouncer outputs, for silencing synth/impl warnings
    
    // BRAM Read Utils
    integer chan_idx, chan_idx_prev, init_iter;
    
    // Debounce all the things (buttons)
    PushButton_Debouncer db_btnC (.clk(clk), .PB(btnC), .PB_state(stable_btnC), .PB_down(dummy_btnC[0]), .PB_up(dummy_btnC[1]));
    
    // Instantiate BRAM
    blk_mem_gen_0 cisr_bram (.clka(clk), .addra(bram_addr), .douta(bram_dout));

    // Generate channels
    generate
        genvar i;
        for (i = 0; i < SM_CHANNEL_COUNT; i = i + 1) begin
        
            cisr_pe_channel pe_channel (.clk(clk), .reset(stable_btnC), .bram_data_end_flag(bram_data_end_flag),
                                        // West Inputs
                                        .value_in(channel_value_in[i]), .col_index_in(channel_col_ind_in[i]), .row_len_in(channel_row_len_in[i]),
                                        // East Outputs
                                        .value_out(channel_value_out[i]), .channel_value_dataempty(channel_value_dataempty[i]), .rowid_out(channel_rowid_out[i]), .channel_rowid_dataempty(channel_rowid_dataempty[i]),
                                        // CISR Inputs/Outputs
                                        .channel_rowid_in(channel_rowid_in[i]), .decoder_rowid_dataempty(decoder_rowid_dataempty[i]), .channel_rowlen_out(channel_rowlen_out[i]),  .channel_rowlen_dataempty(channel_rowlen_dataempty[i]),
                                        .decoder_rowlen_readrequest(fifo_rowlen_read_en[i]),
                                        // Vector Buffer Inputs/Outputs
                                        .vecbuf_vector_in(vecbuf_vector_in[i]), .vecbuf_vector_dataempty(vecbuf_vector_dataempty[i]), .channel_colind_out(channel_colind_out[i]), .channel_colind_dataempty(channel_colind_dataempty[i])  
                                       );
                                       
            cisr_pe_vecbuff pe_vecbuff (.clk(clk), .reset(stable_btnC), .colind_data_in_empty(channel_colind_dataempty[i]), .colind_in(channel_colind_out[i]),
                                        .vector_out(vecbuf_vector_in[i]), .vecbuff_data_empty(vecbuf_vector_dataempty[i])
                                       );
        end        
    endgenerate
    
    // Instantiate CISR Decoder
    cisr_pe_cisrdec pe_cisr_decoder (.clk(clk), .reset(stable_btnC), 
                                     .rowlen_in(channel_rowlen_out), .rowlen_data_in_empty(channel_rowlen_dataempty),
                                     .rowid_out(channel_rowid_in), .rowid_data_empty(decoder_rowid_dataempty), .fifo_rowlen_read_en(fifo_rowlen_read_en)
                                    );
    
    // Initialize structures to acceptible t=0 values
    initial begin
        bram_addr = 4'h0;   // Maximum Address Range: 'h0000 to '7FFE
        chan_idx = 0;
        chan_idx_prev = 0;
        bram_data_start_flag = 0;
        bram_data_end_flag = 0;
        for(init_iter = 0; init_iter < SM_CHANNEL_COUNT-1; init_iter = init_iter + 1) begin
            channel_value_in[init_iter] = 0;
            channel_col_ind_in[init_iter] = 0;
            channel_row_len_in[init_iter] = 0;
            fifo_rowlen_read_en[init_iter] = 0;
        end
    end
    
    // BRAM output assignments for ease of reference
    assign bram_control_val = bram_dout[35:32];
    assign bram_value_val = bram_dout[31:20];
    assign bram_value_colind = bram_dout[19:8];
    assign bram_value_slot = bram_dout[7:0];
    assign bram_rowlen_valid = bram_dout[17:12];
    assign bram_rowlen_val =  bram_dout[11:0];
    
    //
    // Matrix Fetcher Element
    //  Yes, this could've been a module. I didn't feel like bothering to change it at this point.
    //
    always @(posedge clk) begin
        case (bram_addr)
            'h7FFF:
                bram_addr <= 'h7FFF;
            default:
                bram_addr <= bram_addr + 1;
        endcase
        
        case (chan_idx)
            (SM_CHANNEL_COUNT-1): begin
                chan_idx_prev <= chan_idx;
                chan_idx <= 0;
            end
            default: begin
                chan_idx_prev <= chan_idx;
                chan_idx <= chan_idx + 1;
            end
        endcase
        
        // Read the control code from memory
        case (bram_control_val)
            // Code = start of data
            0: begin
                if(bram_dout[31:0] == 'haaaaaaaa) bram_data_start_flag <= 1;// pattern match = data start
            end
            // Code = value
            1: begin
                channel_col_ind_in[chan_idx] <= bram_value_colind;
                channel_value_in[chan_idx] <= bram_value_val;
            end
            // Code = row length
            2: begin
                case (bram_rowlen_valid)
                    1: begin
                        channel_row_len_in[chan_idx_prev] <= bram_rowlen_val; // send row length to the active column from the precious clock cycle 
                                                                          // (clock causes channel index to advance by 1 beyond where the value should really be sent)
                    end
                    default: begin
                            // No more col_ind entries, so do nothing
                    end
                endcase
            end
            // Code = End of Data
            3: begin
                if(bram_dout[31:0] == 'hffffffff) bram_data_end_flag <= 1; // stop the bram data feed
            end
            // Code = Unknown
            default: begin
                if( bram_data_start_flag == 1) bram_data_end_flag <= 1; // only stop the feed if the data start has already been found
            end
        endcase 
    end
    
endmodule

// Module: CISR Processing Element - Channel (aka. Slot)
module cisr_pe_channel    
    #(parameter SM_DATA_INPUT_LENGTH=12, SM_DATA_OUTPUT_LENGTH=12, SM_VECTOR_INPUT_LENGTH=1)
    (input clk, reset,
    
    // West Inputs
     input [SM_DATA_INPUT_LENGTH-1:0] value_in, input [SM_DATA_INPUT_LENGTH-1:0] col_index_in, input [SM_VECTOR_INPUT_LENGTH-1:0] row_len_in, input bram_data_end_flag,
     
     // East Outputs
     output reg [SM_DATA_OUTPUT_LENGTH-1:0] value_out, output reg channel_value_dataempty, output reg [SM_DATA_OUTPUT_LENGTH-1:0] rowid_out, output reg channel_rowid_dataempty,
     
     // CISR Decoder Inputs/Outputs
     output reg [SM_DATA_OUTPUT_LENGTH-1:0] channel_rowlen_out, output reg channel_rowlen_dataempty, input decoder_rowlen_readrequest, input [SM_DATA_OUTPUT_LENGTH-1:0] channel_rowid_in, input decoder_rowid_dataempty,   
     
     // Vector Buffer Inputs/Outputs
     output reg [SM_DATA_OUTPUT_LENGTH-1:0] channel_colind_out, output reg channel_colind_dataempty, input [SM_VECTOR_INPUT_LENGTH-1:0] vecbuf_vector_in, input vecbuf_vector_dataempty 
    );
    
    // FIFO Controls
    reg fifo_rowlen_write_en, fifo_rowlen_read_en;
    reg fifo_colind_write_en, fifo_colind_read_en;
    reg fifo_matval_write_en, fifo_matval_read_en;
    reg fifo_rowid_write_en, fifo_rowid_read_en;
    reg fifo_vector_write_en, fifo_vector_read_en;
    reg fifo_mult_write_en, fifo_mult_read_en;
    
    // FIFO Status
    wire [4:0] fifo_rowlen_status;
    wire [4:0] fifo_colind_status;
    wire [4:0] fifo_matval_status;
    wire [4:0] fifo_rowid_status;
    wire [4:0] fifo_vector_status;
    wire [4:0] fifo_mult_status;
    
    // Interconnect I/O
    reg [SM_DATA_OUTPUT_LENGTH-1:0] fifo_to_cisr_decoder;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] fifo_to_vector_buffer;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] fifo_val_to_multiplier;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] fifo_rowid_to_output;
    reg [SM_VECTOR_INPUT_LENGTH-1:0] fifo_vector_to_multiplier;
    reg [SM_VECTOR_INPUT_LENGTH-1:0] vector_buffer_to_fifo;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] cisr_dec_rowid_to_fifo;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] mult_to_fifo;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] mult_to_fifo_xfer;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] fifo_mult_to_output;
    reg mult_data_empty;    
    
    // Instantiate a FIFO for capturing Row Lengths
    cisr_fifo fifo_rowlen (.clk(clk), .reset(stable_btnC),
                           .write_en(fifo_rowlen_write_en), .read_en(fifo_rowlen_read_en), 
                           .data_in(row_len_in), .data_out(fifo_to_cisr_decoder),
                           .fifo_full_out(fifo_rowlen_status[4]), .fifo_empty_out(fifo_rowlen_status[3]), .fifo_low_water_out(fifo_rowlen_status[2]), .fifo_overflow_out(fifo_rowlen_status[1]), .fifo_underflow_out(fifo_rowlen_status[0]));
                           
    // Instantiate a FIFO for capturing Column Indexes
    cisr_fifo fifo_colind (.clk(clk), .reset(stable_btnC),
                           .write_en(fifo_colind_write_en), .read_en(fifo_colind_read_en), 
                           .data_in(col_index_in), .data_out(fifo_to_vector_buffer),
                           .fifo_full_out(fifo_colind_status[4]), .fifo_empty_out(fifo_colind_status[3]), .fifo_low_water_out(fifo_colind_status[2]), .fifo_overflow_out(fifo_colind_status[1]), .fifo_underflow_out(fifo_colind_status[0]));

    // Instantiate a FIFO for capturing Matrix Values
    cisr_fifo fifo_matval (.clk(clk), .reset(stable_btnC),
                           .write_en(fifo_matval_write_en), .read_en(fifo_matval_read_en), 
                           .data_in(value_in), .data_out(fifo_val_to_multiplier),
                           .fifo_full_out(fifo_matval_status[4]), .fifo_empty_out(fifo_matval_status[3]), .fifo_low_water_out(fifo_matval_status[2]), .fifo_overflow_out(fifo_matval_status[1]), .fifo_underflow_out(fifo_matval_status[0]));

    // Instantiate a FIFO for capturing Row IDs
    cisr_fifo fifo_rowid (.clk(clk), .reset(stable_btnC),
                           .write_en(fifo_rowid_write_en), .read_en(fifo_rowid_read_en), 
                           .data_in(cisr_dec_rowid_to_fifo), .data_out(fifo_rowid_to_output),
                           .fifo_full_out(fifo_rowid_status[4]), .fifo_empty_out(fifo_rowid_status[3]), .fifo_low_water_out(fifo_rowid_status[2]), .fifo_overflow_out(fifo_rowid_status[1]), .fifo_underflow_out(fifo_rowid_status[0]));

    // Instantiate a FIFO for capturing Vector Buffer products
    cisr_fifo fifo_vector (.clk(clk), .reset(stable_btnC),
                           .write_en(fifo_vector_write_en), .read_en(fifo_vector_read_en), 
                           .data_in(vector_buffer_to_fifo), .data_out(fifo_vector_to_multiplier),
                           .fifo_full_out(fifo_vector_status[4]), .fifo_empty_out(fifo_vector_status[3]), .fifo_low_water_out(fifo_vector_status[2]), .fifo_overflow_out(fifo_vector_status[1]), .fifo_underflow_out(fifo_vector_status[0]));

    // Instantiate a FIFO for capturing multiplier products
    cisr_fifo fifo_mult (.clk(clk), .reset(stable_btnC),
                           .write_en(fifo_mult_write_en), .read_en(fifo_mult_read_en), 
                           .data_in(mult_to_fifo_xfer), .data_out(fifo_mult_to_output),
                           .fifo_full_out(fifo_mult_status[4]), .fifo_empty_out(fifo_mult_status[3]), .fifo_low_water_out(fifo_mult_status[2]), .fifo_overflow_out(fifo_mult_status[1]), .fifo_underflow_out(fifo_mult_status[0]));
    
    // Instantiate a multiplier
    cisr_pe_mult mult (.clk(clk), .reset(stable_btnC), .val_data_in_empty(fifo_matval_status[3]), .vector_data_in_empty(fifo_vector_status[3]),
                       .value_in(fifo_val_to_multiplier), .vector_in(fifo_vector_to_multiplier),
                       .product_out(mult_to_fifo), .mult_data_empty(mult_data_empty));
                       
    initial begin
        // FIFO rowlen init
        fifo_rowlen_write_en = 0; // controlled by bram_data_end_flag, starts as off
        fifo_rowlen_read_en = 0; // controlled by decoder_rowlen_readrequest flag, starts as off
        fifo_to_cisr_decoder = 0;
        
        // FIFO colind init
        fifo_colind_write_en = 0; // controlled by bram_data_end_flag, starts as off
        fifo_colind_read_en = 1; // vector buffer module doesnt REALLY care about data, so leaving this on is fine
        fifo_to_vector_buffer = 0;
        
        // FIFO matval init
        fifo_matval_write_en = 0;  // controlled by bram_data_end_flag, starts as off
        fifo_matval_read_en = 0;
        fifo_val_to_multiplier = 0;
        
        // FIFO matval init
        fifo_rowid_write_en = 0; // controlled by decoder_rowid_dataempty flag, starts as off
        fifo_rowid_read_en = 0;
        fifo_rowid_to_output = 0;
        
        // FIFO vector init
        fifo_vector_write_en = 0;
        fifo_vector_read_en = 0;
    end

    always @(posedge clk) begin
        // FIFO capture CISR BRAM inputs
        fifo_rowlen_write_en <= bram_data_end_flag ? 0 : 1;
        fifo_colind_write_en <= bram_data_end_flag ? 0 : 1;
        fifo_matval_write_en <= bram_data_end_flag ? 0 : 1;
        
        // Send FIFO'd row_len to CISR decoder module
        fifo_rowlen_read_en <= decoder_rowlen_readrequest; // only pop/send when requested by the decoder module
        channel_rowlen_out <= fifo_to_cisr_decoder;
        channel_rowlen_dataempty <= fifo_rowlen_status[3];
        
        // Send FIFO'd col_index to Vector Buffer module
        channel_colind_out <= fifo_to_vector_buffer;
        channel_colind_dataempty <= fifo_colind_status[3];
    
        // FIFO capture CISR decoder module products
        cisr_dec_rowid_to_fifo <= channel_rowid_in;
        fifo_rowid_write_en <= decoder_rowid_dataempty ? 0 : 1;
        
        // FIFO capture Vector Buffer mosule products
        vector_buffer_to_fifo <= vecbuf_vector_in;
        fifo_vector_write_en <= vecbuf_vector_dataempty ? 0 : 1;
        
        // FIFO capture multiplier product
        mult_to_fifo_xfer <= mult_to_fifo;
        fifo_mult_write_en <= mult_data_empty ? 0 : 1;
        
        // Multiply vector and value
        // 6a. Send FIFO'd VB product to multiplier
        // 6b. Send FIFO'd values to multipler
    
        // Send CISR decoder module products to East output
        rowid_out <= fifo_rowid_to_output;
        channel_rowid_dataempty <= fifo_rowid_status[3];
        
        // Send FIFO'd multiplier product to East output
        value_out <= fifo_mult_to_output;
        channel_value_dataempty <= fifo_mult_status[3];
    end
endmodule

// Module: CISR Processing Element - Multiplier
module cisr_pe_mult     
    #(parameter SM_DATA_INPUT_LENGTH=12, SM_DATA_OUTPUT_LENGTH=12, SM_VECTOR_INPUT_LENGTH=1)
    (input clk, reset, val_data_in_empty, vector_data_in_empty,
     input [SM_DATA_INPUT_LENGTH-1:0] value_in, input [SM_VECTOR_INPUT_LENGTH-1:0] vector_in,
     output reg [SM_DATA_OUTPUT_LENGTH-1:0] product_out, output reg mult_data_empty);
    
    initial begin
        product_out = 0;
        mult_data_empty = 0;
    end
    
    always @(posedge clk) begin
        if (reset) begin
            product_out = 0;
        end
        else begin
            if( val_data_in_empty | vector_data_in_empty ) product_out <= 0;
            else product_out <= value_in * vector_in;
        end
        
        mult_data_empty <= val_data_in_empty | vector_data_in_empty;
        
    end
endmodule

// Module: CISR Processing Element - Vector Buffer
module cisr_pe_vecbuff     
    #(parameter SM_DATA_INPUT_LENGTH=12, SM_DATA_OUTPUT_LENGTH=12, SM_VECTOR_INPUT_LENGTH=1)
    (input clk, reset, input colind_data_in_empty,
     input [SM_DATA_INPUT_LENGTH-1:0] colind_in,
     output reg [SM_VECTOR_INPUT_LENGTH-1:0] vector_out, output reg vecbuff_data_empty);
    
    initial begin
        vector_out = 0;
        vecbuff_data_empty = 0;
    end
    
    always @(posedge clk) begin
        if (reset) begin
            vector_out = 0;
        end
        else begin
            if( colind_data_in_empty ) vector_out <= 0;
            else vector_out <=  1; // Super lazy, but that's how it is...
        end
        
        vecbuff_data_empty <= colind_data_in_empty;
        
    end
endmodule

// Module: CISR Processing Element - CISR Decoder
module cisr_pe_cisrdec     
    #(parameter SM_DATA_INPUT_LENGTH=12, SM_DATA_OUTPUT_LENGTH=12, SM_VECTOR_INPUT_LENGTH=1, SM_CHANNEL_COUNT=6)
    (input clk, reset, 
     input [SM_DATA_INPUT_LENGTH-1:0] rowlen_in [SM_CHANNEL_COUNT-1:0], input [SM_CHANNEL_COUNT-1:0] rowlen_data_in_empty,
     output reg [SM_DATA_OUTPUT_LENGTH-1:0] rowid_out [SM_CHANNEL_COUNT-1:0], output reg [SM_CHANNEL_COUNT-1:0] rowid_data_empty, output reg [SM_CHANNEL_COUNT-1:0] fifo_rowlen_read_en
    );
    
    integer i, j;
    reg [SM_DATA_OUTPUT_LENGTH-1:0] channel_rowid [SM_CHANNEL_COUNT-1:0]; // Value depth is just a best guess. Probably won't need too many bits for the ID.
    reg [SM_DATA_OUTPUT_LENGTH-1:0] channel_countdown [SM_CHANNEL_COUNT-1:0]; // Value depth is just a best guess. Probably won't need too many bits for the ID.
    reg current_largest_rowid;
    
    initial begin
        rowid_data_empty = 0;
        j = 0; 
        for( i = 0; i < SM_CHANNEL_COUNT; i = i + 1) begin
            rowid_out[i] = 0;
            channel_rowid[i] = i; // Initialize with sequential rowIDs
            channel_countdown[i] = 0;
            fifo_rowlen_read_en[i] = 1; // pull one element from every fifo to start with
        end
        current_largest_rowid = SM_CHANNEL_COUNT - 1; // first max = last channel 
    end
    
    always @(posedge clk) begin
        if (reset) begin
            for( i = 0; i < SM_CHANNEL_COUNT; i = i + 1) begin
                rowid_out[i] = 0;
            end
        end
        
        // Have to iterate through all the channels on each clock tick... don't know how to avoid it.
        for( j = 0; j < SM_CHANNEL_COUNT; j = j + 1 ) begin
            case (channel_countdown[j])
                // If channel counter ran out
                0: begin
                    channel_rowid[j] = current_largest_rowid + 1; // bump the channel to the next available rowID
                    current_largest_rowid = current_largest_rowid + 1; // increment the largest rowID tracker
                    channel_countdown[j] <= rowlen_in[j]; // reset the countdown by pulling in a the next available rowlen
                    fifo_rowlen_read_en[j] <= 1; // enable a rowlen fifo read to refill the rowlen_in reg for this channel
                end
                // If channel counter is still running
                default: begin
                    channel_countdown[j] = channel_countdown[j] - 1; // decrement the countdown by one
                    // Check if rowlen fifo read enable is still on for this channel...
                    case (fifo_rowlen_read_en[j])
                        // ...if it is...
                        1: begin
                            // ...make sure it isn't because of an underflow or empty situation
                            case (rowlen_data_in_empty)
                                1:
                                    fifo_rowlen_read_en[j] <= 1; // if underflow or empty, keep waiting to read in something
                                default:
                                    fifo_rowlen_read_en[j] <= 0; // if not underflow or empty, turn rowlen fifo reads off for this channel
                            endcase
                        end
                        // ...if reads aren't enabled, keep them off for now
                        default:
                            fifo_rowlen_read_en[j] <= 0;
                    endcase
                end
            endcase
            
            // Push the current channel rowID onto its associated rowID output
            rowid_out[j] <= channel_rowid[j];
            
        end
        
    end
endmodule

// Module: CISR I/O Element - FIFO
// ref: https://www.fpga4student.com/2017/01/verilog-code-for-fifo-memory.html
module cisr_fifo
    #(parameter SM_DATA_OUTPUT_LENGTH=12, SM_FIFO_QUEUE_DEPTH=32)
    (input clk, reset, write_en, read_en,
     input [SM_DATA_OUTPUT_LENGTH-1:0] data_in, output [SM_DATA_OUTPUT_LENGTH-1:0] data_out, // Using SM_DATA_OUTPUT_LENGTH here since it represents the largest value we may need to use a FIFO for
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
     reg [SM_DATA_OUTPUT_LENGTH-1:0] int_data_out, int_data_in;
     reg [SM_DATA_OUTPUT_LENGTH-1:0] fifo_memory [SM_FIFO_QUEUE_DEPTH-1:0];
     integer i; // for initializing fifo memory
     
     initial begin
        int_data_out = 0;
        int_data_in = 0;
        for( i = 0; i < SM_DATA_OUTPUT_LENGTH; i = i + 1) begin
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
     assign pointer_equal = (write_ptr[3:0] - read_ptr[3:0]) ? 0 : 1;  
     assign pointer_result = write_ptr[4:0] - read_ptr[4:0];  
     
     // Assign status flags to FIFO module outputs
     assign fifo_overflow_out = fifo_full_flag & write_en;  
     assign fifo_underflow_out = fifo_empty_flag & read_en;  
     assign fifo_low_water_out = low_water_flag;
     
     // Evaluate for FIFO full, empty, or "low water threshold" states
     always @(*) begin  
        fifo_full_flag = ptr_full_bit_comp & pointer_equal;  
        fifo_empty_flag = (~ptr_full_bit_comp) & pointer_equal;  
        low_water_flag = (pointer_result[4] || pointer_result[3]) ? 1 : 0;  
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