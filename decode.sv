import config_pkg::*;
import cpu_types_pkg::*;

module id (
    input  logic                clock,
    input  logic                reset,
    input  logic [9:0]          if_id_pc,
    input  logic [31:0]         if_id_opcode,
    input  logic                stall,              
    input  logic                flush,              
    input  logic                dispatch_success_i, 
    
    output logic                id_valid,
    output logic [9:0]          id_pc,
    output decoded_instruction_t decoded_instruction
);

    decoded_instruction_t comb_dec;
    always_comb begin
        comb_dec = '0; 
        comb_dec.opcode       = if_id_opcode[7:0];   
        comb_dec.operand1_reg = if_id_opcode[12:8];  
        comb_dec.operand2_reg = if_id_opcode[17:13]; 
        comb_dec.result_reg   = if_id_opcode[22:18]; 
        comb_dec.immediate    = if_id_opcode[31:24];
        comb_dec.pc           = if_id_pc;

        if (comb_dec.opcode == OPCODE_LOAD) begin
            comb_dec.instr_type       = INSTR_LOAD;
            comb_dec.load_destination  = if_id_opcode[22:18];
            comb_dec.load_source       = if_id_opcode[17:8];
        end 
        else if (comb_dec.opcode == OPCODE_STORE) begin
            comb_dec.instr_type        = INSTR_STORE;
            comb_dec.store_source      = if_id_opcode[12:8];
            comb_dec.store_destination = if_id_opcode[22:13];
        end 
        else if (comb_dec.opcode[7:6] == 2'b11) begin
            comb_dec.instr_type = INSTR_BRANCH;
        end 
        else begin
            comb_dec.instr_type = (if_id_opcode == 32'b0) ? INSTR_OTHER : INSTR_ALU;
        end
    end


    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            id_pc               <= 10'd0;
            decoded_instruction <= '0;
            id_valid            <= 1'b0;
        end 
        else if (flush) begin
            id_pc               <= 10'd0;
            decoded_instruction <= '0;
            id_valid            <= 1'b0;
        end 
        else if (dispatch_success_i) begin
            id_valid <= 1'b0;
        end 
        else if (!stall && (if_id_opcode != 32'd0)) begin
            id_pc               <= if_id_pc;
            decoded_instruction <= comb_dec; 
            id_valid            <= 1'b1;
        end
    end
endmodule
