package config_pkg;
    parameter FU_ADD_SUB = 3'b000;
    parameter FU_LOGICAL = 3'b011;
    parameter FU_SHIFT   = 3'b100;
    parameter FU_SPECIAL = 3'b111; 

    parameter OPCODE_ADD     = {FU_ADD_SUB, 5'b00000}; 
    parameter OPCODE_SUB     = {FU_ADD_SUB, 5'b00001}; 
    parameter OPCODE_ADDI    = {FU_ADD_SUB, 5'b00010}; 
    parameter OPCODE_SUBI    = {FU_ADD_SUB, 5'b00101}; 

    parameter OPCODE_AND     = {FU_LOGICAL, 5'b00000}; 
    parameter OPCODE_OR      = {FU_LOGICAL, 5'b00001}; 
    parameter OPCODE_XOR     = {FU_LOGICAL, 5'b00010}; 
    parameter OPCODE_ANDI    = {FU_LOGICAL, 5'b00100}; 
    parameter OPCODE_ORI     = {FU_LOGICAL, 5'b00101}; 
    parameter OPCODE_XORI    = {FU_LOGICAL, 5'b00110}; 

    parameter OPCODE_SLL     = {FU_SHIFT,   5'b00000}; 
    parameter OPCODE_SRL     = {FU_SHIFT,   5'b00001}; 
    parameter OPCODE_SRA     = {FU_SHIFT,   5'b00010}; 
    parameter OPCODE_SLLI    = {FU_SHIFT,   5'b00100}; 
    parameter OPCODE_SRLI    = {FU_SHIFT,   5'b00101}; 
    parameter OPCODE_SRAI    = {FU_SHIFT,   5'b00110}; 

    parameter OPCODE_LOAD    = 8'h03; 
    parameter OPCODE_STORE   = 8'h04;

    parameter OPCODE_COMPARE = {FU_SPECIAL, 5'b00001}; 
    
    parameter JE   = 8'b11000100; 
    parameter JNE  = 8'b11000010; 
    parameter JLT  = 8'b11000000; 
    parameter JGE  = 8'b11000101; 
    parameter JLTU = 8'b11000110; 
    parameter JGEU = 8'b11000111; 
    parameter JAL  = 8'b11010000; 
    parameter JALR = 8'b11010001; 

    parameter RV32_LOAD   = 7'b0000011; 
    parameter RV32_STORE  = 7'b0100011; 
    parameter RV32_BRANCH = 7'b1100011; 
    parameter RV32_OP_IMM = 7'b0010011; 
    parameter RV32_OP     = 7'b0110011; 
    parameter RV32_LUI    = 7'b0110111;
    parameter RV32_AUIPC  = 7'b0010111;
    parameter RV32_JAL    = 7'b1101111;
    parameter RV32_JALR   = 7'b1100111;

    parameter RV32_F3_ADD_SUB = 3'b000;
    parameter RV32_F3_SLL     = 3'b001;
    parameter RV32_F3_SLT     = 3'b010;
    parameter RV32_F3_SLTU    = 3'b011;
    parameter RV32_F3_XOR     = 3'b100;
    parameter RV32_F3_SR      = 3'b101;
    parameter RV32_F3_OR      = 3'b110;
    parameter RV32_F3_AND     = 3'b111;
endpackage

package cpu_types_pkg;
    import config_pkg::*;

    typedef enum logic [2:0] {
        INSTR_ALU,
        INSTR_LOAD,
        INSTR_STORE,
        INSTR_BRANCH,
        INSTR_OTHER
    } instruction_type_e;

    typedef struct packed {
        logic [7:0]        opcode;
        instruction_type_e instr_type;
        logic [4:0]        operand1_reg;
        logic [4:0]        operand2_reg;
        logic [4:0]        result_reg;
        logic [31:0]       immediate;
        logic [9:0]        pc; 
        logic              predicted_taken;  
        logic [9:0]        predicted_target;
    } decoded_instruction_t;

    typedef struct packed {
        decoded_instruction_t inst;
        logic [9:0]           pc;
        logic [4:0]           rob_idx; 
        logic                 op1_is_ready;
        logic [4:0]           op1_rob_tag; 
        logic                 op2_is_ready;
        logic [4:0]           op2_rob_tag;
        logic                 store_data_is_ready;
        logic [4:0]           store_data_rob_tag;
    } renamed_instruction_t;

	typedef struct packed {
        logic [31:0] pc;
        logic [7:0]  opcode;
        instruction_type_e instr_type;
        logic [4:0]  rd_idx;      
        logic        is_mispredicted; 
        logic        pred_taken;     
    } rob_instruction_metadata_t;
    typedef struct packed {
        logic        busy;
        logic        is_complete;
        logic        has_exception;
        rob_instruction_metadata_t inst_data;
        logic [31:0] result_value;
    } rob_entry_t;

    typedef struct packed {
        logic [7:0]  opcode;
        logic [4:0]  rob_idx;
        logic [4:0]  dest_reg;
        logic        op1_is_ready;
        logic [31:0] op1_val;
        logic [4:0]  op1_rob_tag;
        logic        op2_is_ready;
        logic [31:0] op2_val;
        logic [4:0]  op2_rob_tag;
    } alu_dispatch_packet_t;

    typedef struct packed {
        logic [7:0]  opcode;
        logic [4:0]  rob_idx;
        logic [4:0]  dest_reg;
        logic [31:0] immediate; 
        logic        addr_op_is_ready;
        logic [31:0] addr_op_val;
        logic [4:0]  addr_op_rob_tag;
        logic        data_op_is_ready;
        logic [31:0] data_op_val;
        logic [4:0]  data_op_rob_tag;
    } lsu_dispatch_packet_t;

    typedef struct packed {
        logic [7:0]  opcode;
        logic [4:0]  rob_idx;
        logic [31:0] pc;
        logic [31:0] immediate; 
        logic        operand1_ready;
        logic [31:0] operand1_val;
        logic [4:0]  operand1_rob_tag;
        logic        operand2_ready;
        logic [31:0] operand2_val;
        logic [4:0]  operand2_rob_tag;
        logic        predicted_taken;  
        logic [9:0]  predicted_target; 
    } branch_dispatch_packet_t;


    typedef struct packed {
        logic        busy;
        logic [7:0]  opcode;
        logic [4:0]  rob_idx;
        logic [4:0]  dest_reg;
        logic        Vj_valid;
        logic [31:0] V_j;
        logic [4:0]  Qj;
        logic        Vk_valid;
        logic [31:0] V_k;
        logic [4:0]  Qk;
    } alu_rs_entry_t;

    typedef struct packed {
        logic        busy;
        logic [7:0]  opcode;
        logic [4:0]  rob_idx;
        logic [31:0] pc;
        logic [31:0] imm; 
        logic        Vj_ready;
        logic [31:0] Vj_data;
        logic [4:0]  Qj;
        logic        Vk_ready;
        logic [31:0] Vk_data;
        logic [4:0]  Qk;
        logic        pred_taken;  
        logic [9:0]  pred_target; 
    } branch_rs_entry_t;

endpackage
