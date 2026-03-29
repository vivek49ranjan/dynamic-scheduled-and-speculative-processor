import config_pkg::*;
import cpu_types_pkg::*;

module dispatch_stage (
    input  logic clk, reset, flush_i,
    
    input  logic                 renamed_valid_i,
    input  renamed_instruction_t renamed_inst_i,
    
    output logic [4:0]  rf_raddr1_o, rf_raddr2_o,
    input  logic [31:0] rf_rdata1_i, rf_rdata2_i,
    
    input  logic        commit_wen_i,
    input  logic [4:0]  commit_waddr_i,
    input  logic [31:0] commit_wdata_i,
    
    input  logic rob_full_i, 
    input  logic alu_rs_full_i, 
    input  logic lsq_rs_full_i, 
    input  logic branch_rs_full_i,
    
    input  logic [3:0]  lsq_next_idx_i, 
    
    output logic dispatch_success_o, 
    output logic rename_stall_o,     
    
    output logic                    rob_allocate_valid_o,
    output rob_instruction_metadata_t rob_allocate_data_o,
    
    output logic                    to_alu_valid_o,
    output alu_dispatch_packet_t    to_alu_packet_o,
    output logic                    to_lsu_valid_o,
    output lsu_dispatch_packet_t    to_lsu_packet_o,
    output logic                    to_branch_valid_o,
    output branch_dispatch_packet_t to_branch_packet_o
);

    logic [31:0] sign_extended_imm;
    logic        is_alu_imm;

    assign sign_extended_imm = renamed_inst_i.inst.immediate;
    
    assign is_alu_imm = (renamed_inst_i.inst.opcode == OPCODE_ADDI) || 
                        (renamed_inst_i.inst.opcode == OPCODE_SUBI) || 
                        (renamed_inst_i.inst.opcode == OPCODE_ANDI) || 
                        (renamed_inst_i.inst.opcode == OPCODE_ORI)  ||
                        (renamed_inst_i.inst.opcode == OPCODE_XORI) ||
                        (renamed_inst_i.inst.opcode == OPCODE_SLLI) ||
                        (renamed_inst_i.inst.opcode == OPCODE_SRLI) ||
                        (renamed_inst_i.inst.opcode == OPCODE_SRAI);

    always_comb begin
        logic rs_has_space;
        case (renamed_inst_i.inst.instr_type)
            INSTR_ALU:    rs_has_space = !alu_rs_full_i;
            INSTR_LOAD,
            INSTR_STORE:  rs_has_space = !lsq_rs_full_i;
            INSTR_BRANCH: rs_has_space = !branch_rs_full_i;
            default:      rs_has_space = 1'b1;
        endcase

        rename_stall_o = rob_full_i || !rs_has_space;
        dispatch_success_o = renamed_valid_i && !rename_stall_o && !flush_i;
    end

    always_comb begin
        rf_raddr1_o = renamed_inst_i.inst.operand1_reg;
        rf_raddr2_o = (renamed_inst_i.inst.instr_type == INSTR_STORE) ? 
                       renamed_inst_i.inst.store_source : renamed_inst_i.inst.operand2_reg;
    end

    always_comb begin
        rob_allocate_valid_o = 1'b0;
        rob_allocate_data_o  = '0;
        {to_alu_valid_o, to_lsu_valid_o, to_branch_valid_o} = '0;
        {to_alu_packet_o, to_lsu_packet_o, to_branch_packet_o} = '0;

        if (dispatch_success_o) begin
            rob_allocate_valid_o = 1'b1;
            rob_allocate_data_o.pc          = {22'b0, renamed_inst_i.pc};
            rob_allocate_data_o.opcode      = renamed_inst_i.inst.opcode;
            rob_allocate_data_o.instr_type = renamed_inst_i.inst.instr_type;
            rob_allocate_data_o.rd_idx      = renamed_inst_i.inst.result_reg;
            rob_allocate_data_o.lsq_idx     = {1'b0, lsq_next_idx_i};

            case (renamed_inst_i.inst.instr_type)
                INSTR_ALU: begin
                    to_alu_valid_o = 1'b1;
                    to_alu_packet_o.opcode      = renamed_inst_i.inst.opcode;
                    to_alu_packet_o.rob_idx     = renamed_inst_i.rob_idx;
                    to_alu_packet_o.dest_reg    = renamed_inst_i.inst.result_reg;
                    
                    if (commit_wen_i && commit_waddr_i == rf_raddr1_o && rf_raddr1_o != 0) begin
                        to_alu_packet_o.op1_val      = commit_wdata_i;
                        to_alu_packet_o.op1_is_ready = 1'b1;
                    end else begin
                        to_alu_packet_o.op1_val      = rf_rdata1_i;
                        to_alu_packet_o.op1_is_ready = renamed_inst_i.op1_is_ready;
                    end
                    to_alu_packet_o.op1_rob_tag = renamed_inst_i.op1_rob_tag;

                    if (is_alu_imm) begin
                        to_alu_packet_o.op2_val      = sign_extended_imm;
                        to_alu_packet_o.op2_is_ready = 1'b1;
                        to_alu_packet_o.op2_rob_tag  = 5'h0;
                    end else if (commit_wen_i && commit_waddr_i == rf_raddr2_o && rf_raddr2_o != 0) begin
                        to_alu_packet_o.op2_val      = commit_wdata_i;
                        to_alu_packet_o.op2_is_ready = 1'b1;
                        to_alu_packet_o.op2_rob_tag  = renamed_inst_i.op2_rob_tag;
                    end else begin
                        to_alu_packet_o.op2_val      = rf_rdata2_i;
                        to_alu_packet_o.op2_is_ready = renamed_inst_i.op2_is_ready;
                        to_alu_packet_o.op2_rob_tag  = renamed_inst_i.op2_rob_tag;
                    end
                end

                INSTR_LOAD, INSTR_STORE: begin
                    to_lsu_valid_o = 1'b1;
                    to_lsu_packet_o.opcode    = renamed_inst_i.inst.opcode;
                    to_lsu_packet_o.immediate = sign_extended_imm; 
                    to_lsu_packet_o.rob_idx   = renamed_inst_i.rob_idx;
                    to_lsu_packet_o.lsq_idx   = {1'b0, lsq_next_idx_i}; 
                    to_lsu_packet_o.dest_reg  = renamed_inst_i.inst.result_reg;
                    
                    to_lsu_packet_o.addr_op_val      = (commit_wen_i && commit_waddr_i == rf_raddr1_o && rf_raddr1_o != 0) ? commit_wdata_i : rf_rdata1_i;
                    to_lsu_packet_o.addr_op_is_ready = (commit_wen_i && commit_waddr_i == rf_raddr1_o && rf_raddr1_o != 0) ? 1'b1 : renamed_inst_i.op1_is_ready;
                    to_lsu_packet_o.addr_op_rob_tag  = renamed_inst_i.op1_rob_tag;
                    
                    to_lsu_packet_o.data_op_val      = (commit_wen_i && commit_waddr_i == rf_raddr2_o && rf_raddr2_o != 0) ? commit_wdata_i : rf_rdata2_i;
                    to_lsu_packet_o.data_op_is_ready = (commit_wen_i && commit_waddr_i == rf_raddr2_o && rf_raddr2_o != 0) ? 1'b1 : renamed_inst_i.op2_is_ready;
                    to_lsu_packet_o.data_op_rob_tag  = renamed_inst_i.op2_rob_tag;
                end

                INSTR_BRANCH: begin
                    to_branch_valid_o = 1'b1;
                    to_branch_packet_o.opcode    = renamed_inst_i.inst.opcode;
                    to_branch_packet_o.rob_idx   = renamed_inst_i.rob_idx;
                    to_branch_packet_o.pc        = {22'b0, renamed_inst_i.pc};
                    to_branch_packet_o.immediate = sign_extended_imm; 
                    
                    to_branch_packet_o.operand1_val   = (commit_wen_i && commit_waddr_i == rf_raddr1_o && rf_raddr1_o != 0) ? commit_wdata_i : rf_rdata1_i;
                    to_branch_packet_o.operand1_ready = (commit_wen_i && commit_waddr_i == rf_raddr1_o && rf_raddr1_o != 0) ? 1'b1 : renamed_inst_i.op1_is_ready;
                    to_branch_packet_o.operand1_rob_tag = renamed_inst_i.op1_rob_tag;

                    to_branch_packet_o.operand2_val   = (commit_wen_i && commit_waddr_i == rf_raddr2_o && rf_raddr2_o != 0) ? commit_wdata_i : rf_rdata2_i;
                    to_branch_packet_o.operand2_ready = (commit_wen_i && commit_waddr_i == rf_raddr2_o && rf_raddr2_o != 0) ? 1'b1 : renamed_inst_i.op2_is_ready;
                    to_branch_packet_o.operand2_rob_tag = renamed_inst_i.op2_rob_tag;
                end
                
                default: ;
            endcase
        end
    end
endmodule
