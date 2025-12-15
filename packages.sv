package config_pkg;
    // ALU Operation Encodings
    parameter FU_ADD_SUB = 3'b000;
    parameter FU_LOGICAL = 3'b011;
    parameter FU_SHIFT   = 3'b100;
    parameter FU_ROTATE  = 3'b101;
    parameter FU_INC_DEC = 3'b110;
    parameter FU_SPECIAL = 3'b111;

    parameter SUB_ABS     = 3'b000;
    parameter SUB_COMPARE = 3'b001;

    // Full Opcodes
    parameter OPCODE_ADD     = {FU_ADD_SUB, 3'b000};
    parameter OPCODE_SUB     = {FU_ADD_SUB, 3'b001};
    parameter OPCODE_AND     = {FU_LOGICAL, 3'b000};
    parameter OPCODE_OR      = {FU_LOGICAL, 3'b001};
    parameter OPCODE_XOR     = {FU_LOGICAL, 3'b010};
    parameter OPCODE_NOT     = {FU_LOGICAL, 3'b011};
    parameter OPCODE_SLL     = {FU_SHIFT,   3'b000};
    parameter OPCODE_SRL     = {FU_SHIFT,   3'b001};
    parameter OPCODE_ROTL    = {FU_ROTATE,  3'b000};
    parameter OPCODE_ROTR    = {FU_ROTATE,  3'b001};
    parameter OPCODE_INC     = {FU_INC_DEC, 3'b000};
    parameter OPCODE_DEC     = {FU_INC_DEC, 3'b001};
    parameter OPCODE_ABS     = {FU_SPECIAL, SUB_ABS};
    parameter OPCODE_COMPARE = {FU_SPECIAL, SUB_COMPARE};
    
    // Branch Opcodes
    parameter FU_BRANCH = 3'b111; // Reserved in top opcode
    parameter JLT = 8'b11000000;
    parameter JGT = 8'b11000001;
    parameter JNE = 8'b11000010;
    parameter JLE = 8'b11000011;
    parameter JE  = 8'b11000100;
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

    // Decoded Instruction Format
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
    } decoded_instruction_t;

    // Renamed Instruction Format
    typedef struct packed {
        decoded_instruction_t inst;
        logic [9:0]           pc;
        logic [3:0]           rob_idx;
        logic                 op1_is_ready;
        logic [3:0]           op1_rob_tag;
        logic [31:0]          op1_data;
        logic                 op2_is_ready;
        logic [3:0]           op2_rob_tag;
        logic [31:0]          op2_data;
        logic                 store_data_is_ready;
        logic [3:0]           store_data_rob_tag;
        logic [31:0]          store_data;
    } renamed_instruction_t;

    // ROB Structures
    typedef struct packed {
        logic [31:0] pc;
        logic [7:0]  opcode;
        instruction_type_e instr_type;
        logic [4:0]  rd_idx;      // Architecture Destination Reg
        logic [4:0]  store_src_reg;
        logic [31:0] branch_target;
        logic [3:0]  lsq_idx;
    } rob_instruction_metadata_t;

    typedef struct packed {
        logic        busy;
        logic        is_complete;
        logic        has_exception;
        rob_instruction_metadata_t inst_data;
        logic [31:0] result_value;
    } rob_entry_t;

    // Dispatch Packets
    typedef struct packed {
        logic [7:0]  opcode;
        logic [3:0]  rob_idx;
        logic [4:0]  dest_reg;
        logic        op1_is_ready;
        logic [31:0] op1_val;
        logic [3:0]  op1_rob_tag;
        logic        op2_is_ready;
        logic [31:0] op2_val;
        logic [3:0]  op2_rob_tag;
    } alu_dispatch_packet_t;

    typedef struct packed {
        logic [7:0]  opcode;
        logic [3:0]  rob_idx;
        logic [3:0]  lsq_idx;
        logic        addr_op_is_ready;
        logic [31:0] addr_op_val;
        logic [3:0]  addr_op_rob_tag;
        logic        data_op_is_ready;
        logic [31:0] data_op_val;
        logic [3:0]  data_op_rob_tag;
        logic [4:0]  dest_reg;
    } lsu_dispatch_packet_t;

    typedef struct packed {
        logic [7:0]  opcode;
        logic [31:0] operand1_val;
        logic [31:0] operand2_val;
        logic        operand1_ready;
        logic        operand2_ready;
        logic [3:0]  operand1_rob_tag;
        logic [3:0]  operand2_rob_tag;
        logic [3:0]  rob_idx;
        logic [31:0] pc;
    } branch_dispatch_packet_t;

    // Queue Packets
    typedef struct packed {
        logic [7:0]  opcode;
        logic [4:0]  dest_reg_addr;
        logic [31:0] op1_val;
        logic [31:0] op2_val;
        logic [4:0]  load_destination;
        logic [4:0]  store_source;
        logic [7:0]  load_source;
        logic [7:0]  store_destination;
        logic [3:0]  rob_id;
    } instruction_queue_packet_t;

    // Reservation Station Internal Types
    typedef struct packed {
        logic        valid;
        logic        ready;    // Operands are ready
        logic        fu_ready; // Functional Unit is free
        logic [3:0]  rob_idx;
    } rs_status_t;

    typedef struct packed {
        logic        busy;
        logic [7:0]  opcode;
        logic        Vj_valid;
        logic [31:0] V_j;
        logic [3:0]  Qj;
        logic        Vk_valid;
        logic [31:0] V_k;
        logic [3:0]  Qk;
        logic [4:0]  dest_reg;
        logic [3:0]  rob_idx;
    } alu_rs_entry_t;
    
    typedef enum logic [1:0] {
        MEM_IDLE,
        MEM_ACCESSING,
        MEM_COMPLETE
    } mem_access_state_t;

endpackage


