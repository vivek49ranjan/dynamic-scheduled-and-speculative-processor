`timescale 1ns / 1ps

// ============================================================================
// 1. CONFIGURATION PACKAGE: Hardware Constants and Opcode Encodings
// ============================================================================
package config_pkg;
    // ALU Operation Functional Unit Encodings (Top 3 bits of opcode)
    parameter FU_ADD_SUB = 3'b000;
    parameter FU_LOGICAL = 3'b011;
    parameter FU_SHIFT   = 3'b100;
    parameter FU_ROTATE  = 3'b101;
    parameter FU_INC_DEC = 3'b110;
    parameter FU_SPECIAL = 3'b111;

    // Sub-operation codes for FU_SPECIAL
    parameter SUB_ABS     = 3'b000;
    parameter SUB_COMPARE = 3'b001;

    // --- ARITHMETIC OPCODES ---
    parameter OPCODE_ADD     = {FU_ADD_SUB, 3'b000}; // 8'h00
    parameter OPCODE_SUB     = {FU_ADD_SUB, 3'b001}; // 8'h01
    parameter OPCODE_ADDI    = {FU_ADD_SUB, 3'b010}; // 8'h02
    parameter OPCODE_SUBI    = {FU_ADD_SUB, 3'b101}; // 8'h05 

    // --- LOGICAL OPCODES ---
    parameter OPCODE_AND     = {FU_LOGICAL, 3'b000};
    parameter OPCODE_OR      = {FU_LOGICAL, 3'b001};
    parameter OPCODE_XOR     = {FU_LOGICAL, 3'b010};
    parameter OPCODE_NOT     = {FU_LOGICAL, 3'b011};
    parameter OPCODE_ANDI    = {FU_LOGICAL, 3'b100};
    parameter OPCODE_ORI     = {FU_LOGICAL, 3'b101};
    parameter OPCODE_XORI    = {FU_LOGICAL, 3'b110};

    // --- SHIFT OPCODES ---
    parameter OPCODE_SLL     = {FU_SHIFT,   3'b000};
    parameter OPCODE_SRL     = {FU_SHIFT,   3'b001};
    parameter OPCODE_SLLI    = {FU_SHIFT,   3'b100};
    parameter OPCODE_SRLI    = {FU_SHIFT,   3'b101};

    // --- MEMORY OPCODES (FIXES ERROR 10161) ---
    parameter OPCODE_LOAD    = 8'h03; 
    parameter OPCODE_STORE   = 8'h04;

    // --- OTHER OPCODES ---
    parameter OPCODE_ROTL    = {FU_ROTATE,  3'b000};
    parameter OPCODE_ROTR    = {FU_ROTATE,  3'b001};
    parameter OPCODE_INC     = {FU_INC_DEC, 3'b000};
    parameter OPCODE_DEC     = {FU_INC_DEC, 3'b001};
    parameter OPCODE_ABS     = {FU_SPECIAL, SUB_ABS};
    parameter OPCODE_COMPARE = {FU_SPECIAL, SUB_COMPARE};
    
    // --- BRANCH OPCODES ---
    parameter FU_BRANCH = 3'b111; 
    parameter JLT = 8'b11000000;
    parameter JGT = 8'b11000001;
    parameter JNE = 8'b11000010;
    parameter JLE = 8'b11000011;
    parameter JE  = 8'b11000100;
endpackage

// ============================================================================
// 2. CPU TYPES PACKAGE: Structs, Enums, and Data Flow Objects
// ============================================================================
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
        logic [4:0]        load_destination;
        logic [9:0]        load_source;
        logic [4:0]        store_source;
        logic [9:0]        store_destination;
        logic [7:0]        immediate;
        logic [9:0]        pc; 
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
        logic [4:0]  store_src_reg;
        logic [31:0] branch_target;
        logic [4:0]  lsq_idx; 
        logic        is_mispredicted; // <--- ADD THIS LINE
    } rob_instruction_metadata_t;

    typedef struct packed {
        logic        busy;
        logic        is_complete;
        logic        has_exception;
        rob_instruction_metadata_t inst_data;
        logic [31:0] result_value;
    } rob_entry_t;

    // --- Dispatch Packets ---
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
        logic [4:0]  lsq_idx;
        logic [4:0]  dest_reg;
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
        logic [7:0]  immediate;
        logic        operand1_ready;
        logic [31:0] operand1_val;
        logic [4:0]  operand1_rob_tag;
        logic        operand2_ready;
        logic [31:0] operand2_val;
        logic [4:0]  operand2_rob_tag;
    } branch_dispatch_packet_t;

    typedef struct packed {
        logic        valid;
        logic        ready;
        logic        fu_ready;
        logic [4:0]  rob_idx;
    } rs_status_t;

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
        logic [7:0]  imm;
        logic        Vj_ready;
        logic [31:0] Vj_data;
        logic [4:0]  Vj_rob_tag;
        logic        Vk_ready;
        logic [31:0] Vk_data;
        logic [4:0]  Vk_rob_tag;
    } branch_rs_entry_t;

    typedef enum logic [1:0] {
        MEM_IDLE,
        MEM_ACCESSING,
        MEM_COMPLETE
    } mem_access_state_t;
endpackage
