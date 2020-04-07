`timescale 1ns / 1ps


//Module to take two strings and output how long their prefixes match
//Based on:
//MODULAR DESIGN OF FAST LEADING ZEROS COUNTING CIRCUIT
//Journal of ELECTRICAL ENGINEERING, VOL. 66, NO. 6, 2015, 329-333
module prefix_len_finder
(
    input wire [7:0] str_1[14:0],
    input wire [7:0] str_2[14:0],
    output reg [3:0] prefix_len
);
    wire [15:0] byte_matches;
    wire [3:0] nibbles [3:0];
    wire all_one_nibbles[3:0];
    assign byte_matches[15] = 1'b0;
    generate
        genvar i;
        for(i = 0; i < 15; i++) begin
            assign byte_matches[i] = (str_1[i] == str_2[i]);
        end
        for(i = 0; i < 4; i++) begin
            assign nibbles[i] = byte_matches[(i*4)+:4];
            assign all_one_nibbles[i] = &nibbles[i];
        end
    endgenerate
    
    always_comb begin
        prefix_len = 15;
        for(int i = 3; i >= 0; i--) begin
            if(!all_one_nibbles[i]) begin
                prefix_len = (i*4) + (&nibbles[i][2:0] ? 3 :
                                    &nibbles[i][1:0] ? 2 :
                                    nibbles[i][0] ? 1 : 0);
            end
        end
    end
endmodule

module max_prefix(
//Inputs
    input wire clk,
    input wire rst,
    input wire push,//if high, write the next byte into the sliding window and increment cur_write_pos
    input wire search,//If high, start searching routine, setting busy to high until it is done
    input wire[7:0] byte_in,
//Outputs
    output wire waiting,
    output wire busy,
    output reg res_valid,
    output reg[11:0] max_pos_out,
    output reg[3:0] max_len
);
//Internal states and signals
(* memory_type = "distributed" *) reg [7:0] window[4095:0];//Sliding window
(* memory_type = "register" *) reg [7:0] buffer[14:0];//Lookahead buffer
    reg [11:0] max_pos, cur_write_pos, cur_read_pos;
    wire [3:0] cur_len;
    wire [7:0] window_slice[14:0];
//This places an upper limit on the number of writes the core can take as 2^64
    reg[63:0] writes_since_last_reset, positions_searched;
    typedef enum {
        ready,//Able to accept a new byte or start searching
        searching,//Busy, searching for match
        clearing//Busy, clearing sliding window
    } State;
    
    State s;
    
//Initialize everything
    initial begin
        for(int i = 0; i < 4096; i++) begin
            window[i] = 0;
        end
        for(int i = 0; i < 15; i++) begin
            buffer[i] = 0;
        end
        max_pos = 0;
        cur_write_pos = 0;
        cur_read_pos = 0;
        max_len = 0;
        res_valid = 0;
        max_pos_out = 0;
        s = ready;
        writes_since_last_reset = 0;
        positions_searched = 0;
    end
//Set up 15-character slice into sliding window
    generate
        genvar i;
        for(i = 0; i < 15; i++) begin
            assign window_slice[i] = window[(i + cur_read_pos)% 4096];
        end
    endgenerate

//Wire up prefix finder and status signals
    wire[3:0] pf_cur_len;
    prefix_len_finder plf(buffer, window_slice, pf_cur_len);
//Big mess to account for data extending beyond the head of the sliding window being invalid
    wire [11:0] abs_cur_read_write_pos_diff;
    assign abs_cur_read_write_pos_diff = cur_write_pos >= cur_read_pos ? cur_write_pos - cur_read_pos : cur_write_pos + (4096 - max_pos);
    assign cur_len = pf_cur_len > abs_cur_read_write_pos_diff ? abs_cur_read_write_pos_diff : pf_cur_len;

    assign waiting = s == ready;
    assign busy = s == searching || s == clearing;

//If we're pushing, push. If we're searching, search or assert search is done
//That's all this does.
//State actions + transitions
    always@(posedge clk) begin
        if(rst) begin//Re-init everything except window as it is dram
            for(int i = 0; i < 15; i++) begin
                buffer[i] = 0;
            end
            max_pos = 0;
            cur_write_pos = 0;
            cur_read_pos = 0;
            max_len = 0;
            res_valid = 0;
            max_pos_out = 0;
            s = clearing;
        end else if(s == ready) begin
            if(push) begin
                window[cur_write_pos] = buffer[0];
                for(int i = 0; i < 14; i++) begin
                    buffer[i] = buffer[i+1];
                end
                buffer[14] = byte_in;
                cur_write_pos += 1;
                cur_read_pos += 1;
                writes_since_last_reset += 1;
                res_valid = 0;
            end else if(search && !res_valid) begin//Only search if we haven't already for this data set
                cur_read_pos = cur_write_pos;
                max_pos = 0;
                max_len = 0;
                positions_searched = 0;
                s = searching;
            end
        end else if(s == searching) begin
            if(cur_len > max_len) begin
                max_pos = cur_read_pos;
                max_len = cur_len;
            end
            cur_read_pos -= 1;
            positions_searched += 1;
//We're done searching if we've checked every position or
            if(cur_read_pos - 1 == cur_write_pos ||
//we've checked every position with a valid byte or
//(if thats less than every window position). This is -15 as
//the core initially pushes 15 bytes of null characters into
//the window, as the buffer fills up.
                positions_searched >= (writes_since_last_reset > 15 ? writes_since_last_reset - 15 : 0) ||
//we've found the longest possible substitution
                max_len >= 15) begin
                res_valid = 1;
                max_pos_out = cur_write_pos > max_pos ? cur_write_pos - max_pos : cur_write_pos + (4096 - max_pos);
                s <= ready;
            end
        end else if(s == clearing) begin
            window[cur_write_pos] = 0;
            if(cur_write_pos < 4095 &&
                writes_since_last_reset > 0) begin
                cur_write_pos += 1;
                writes_since_last_reset -= 1;
            end else begin
                writes_since_last_reset = 0;
                cur_write_pos = 0;
                s = ready;
            end
        end
    end

endmodule
