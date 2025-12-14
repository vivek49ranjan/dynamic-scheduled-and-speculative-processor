`define PC_WIDTH 10
`define REG_ADDR_WIDTH 5
`define OPCODE_WIDTH 8
`define IMMEDIATE_WIDTH 8

typedef struct packed {
    logic [`OPCODE_WIDTH-1:0]   opcode;
    logic [`REG_ADDR_WIDTH-1:0] operand1_reg;
    logic [`REG_ADDR_WIDTH-1:0] operand2_reg;
    logic [`REG_ADDR_WIDTH-1:0] result_reg;
    logic [`REG_ADDR_WIDTH-1:0] load_destination;
    logic [9:0]                 load_source;       
    logic [`REG_ADDR_WIDTH-1:0] store_source;
    logic [9:0]                 store_destination;  
    logic [`IMMEDIATE_WIDTH-1:0] immediate;
} decoded_instruction_t;



module id (
    input                       clock,
    input                       reset,
    input [`PC_WIDTH-1:0]       if_id_pc,
    input [31:0]                if_id_opcode,
    input logic                 stall,
    input logic                 flush,
    output logic                id_valid,
    output reg [`PC_WIDTH-1:0]  id_pc,
    output  decoded_instruction_t decoded_instruction
);
	
    decoded_instruction_t comb_decoded_instruction;

    always_comb begin
        comb_decoded_instruction.opcode           = if_id_opcode[31:24];
        comb_decoded_instruction.operand1_reg     = if_id_opcode[23:19];
        comb_decoded_instruction.operand2_reg     = if_id_opcode[18:14];
        comb_decoded_instruction.result_reg       = if_id_opcode[12:8];
        comb_decoded_instruction.load_destination = if_id_opcode[23:19];
        comb_decoded_instruction.load_source      = if_id_opcode[20:11]; 
        comb_decoded_instruction.store_source     = if_id_opcode[15:11];
        comb_decoded_instruction.store_destination= if_id_opcode[25:16]; 
        comb_decoded_instruction.immediate        = if_id_opcode[7:0];
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            id_pc <= '0;
            decoded_instruction <= '0;
            id_valid <= 1'b0;
        end else if (flush) begin
            id_pc <= '0;
            decoded_instruction <= '0;
            id_valid <= 1'b0;
        end else if (stall) begin
            // Hold values on stall
        end else begin
            id_pc <= if_id_pc;
            decoded_instruction <= comb_decoded_instruction;
            id_valid <= 1'b1;
        end
    end

endmodule
