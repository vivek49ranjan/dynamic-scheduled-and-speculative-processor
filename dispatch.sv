module dispatch_stage (
    input  logic                  clk,
    input  logic                  reset,

    input  logic                  renamed_valid_i,
    input  renamed_instruction_t  renamed_inst_i,

    input  logic [3:0]            lsq_next_idx_i,
    input  logic                  rob_full_i,
    input  logic                  alu_rs_full_i,
    input  logic                  lsq_rs_full_i,
    input  logic                  branch_rs_full_i,

    output logic                  rename_stall_o,
    output logic                  dispatch_can_proceed_o,

    output logic                  rob_allocate_valid_o,
    output rob_instruction_metadata_t rob_allocate_data_o,

    output logic                  to_alu_valid_o,
    output alu_dispatch_packet_t  to_alu_packet_o,

    output logic                  to_lsu_valid_o,
    output lsu_dispatch_packet_t  to_lsu_packet_o,

    output logic                  to_branch_valid_o,
    output branch_dispatch_packet_t to_branch_packet_o
);

    import cpu_types_pkg::*;
    import config_pkg::*;

    logic can_dispatch;

    always_comb begin
        can_dispatch = 1'b0;

        if (renamed_valid_i && !rob_full_i) begin
            case (renamed_inst_i.inst.instr_type)
                INSTR_ALU:    can_dispatch = !alu_rs_full_i;
                INSTR_LOAD,
                INSTR_STORE:  can_dispatch = !lsq_rs_full_i;
                INSTR_BRANCH: can_dispatch = !branch_rs_full_i;
                default:      can_dispatch = 1'b0;
            endcase
        end

        rename_stall_o          = renamed_valid_i && !can_dispatch;
        dispatch_can_proceed_o  = can_dispatch;

        rob_allocate_valid_o    = can_dispatch;
        to_alu_valid_o          = can_dispatch && (renamed_inst_i.inst.instr_type == INSTR_ALU);
        to_lsu_valid_o          = can_dispatch && (renamed_inst_i.inst.instr_type == INSTR_LOAD || renamed_inst_i.inst.instr_type == INSTR_STORE);
        to_branch_valid_o       = can_dispatch && (renamed_inst_i.inst.instr_type == INSTR_BRANCH);

        rob_allocate_data_o = '0;
        to_alu_packet_o     = '0;
        to_lsu_packet_o     = '0;
        to_branch_packet_o  = '0;

        if (can_dispatch) begin
            rob_allocate_data_o.pc         = renamed_inst_i.pc;
            rob_allocate_data_o.opcode     = renamed_inst_i.inst.opcode;
            rob_allocate_data_o.instr_type = renamed_inst_i.inst.instr_type;

            case (renamed_inst_i.inst.instr_type)
                INSTR_ALU: begin
                    rob_allocate_data_o.rd_idx = renamed_inst_i.inst.result_reg;
                    
                    to_alu_packet_o.opcode       = renamed_inst_i.inst.opcode;
                    to_alu_packet_o.rob_idx      = renamed_inst_i.rob_idx;
                    to_alu_packet_o.dest_reg     = renamed_inst_i.inst.result_reg;
                    to_alu_packet_o.op1_is_ready = renamed_inst_i.op1_is_ready;
                    to_alu_packet_o.op1_val      = renamed_inst_i.op1_data;
                    to_alu_packet_o.op1_rob_tag  = renamed_inst_i.op1_rob_tag;
                    to_alu_packet_o.op2_is_ready = renamed_inst_i.op2_is_ready;
                    to_alu_packet_o.op2_val      = renamed_inst_i.op2_data;
                    to_alu_packet_o.op2_rob_tag  = renamed_inst_i.op2_rob_tag;
                end

                INSTR_LOAD: begin
                    rob_allocate_data_o.rd_idx = renamed_inst_i.inst.load_destination;
                    rob_allocate_data_o.lsq_idx = lsq_next_idx_i;
                    
                    to_lsu_packet_o.opcode = renamed_inst_i.inst.opcode;
                    to_lsu_packet_o.rob_idx = renamed_inst_i.rob_idx;
                    to_lsu_packet_o.lsq_idx = lsq_next_idx_i;
                    to_lsu_packet_o.dest_reg = renamed_inst_i.inst.load_destination;
                    to_lsu_packet_o.addr_op_is_ready = renamed_inst_i.op1_is_ready;
                    to_lsu_packet_o.addr_op_val = renamed_inst_i.op1_data;
                    to_lsu_packet_o.addr_op_rob_tag = renamed_inst_i.op1_rob_tag;
                end

                INSTR_STORE: begin
                    rob_allocate_data_o.store_src_reg = renamed_inst_i.inst.store_source;
                    rob_allocate_data_o.lsq_idx       = lsq_next_idx_i;
                    
                    to_lsu_packet_o.opcode = renamed_inst_i.inst.opcode;
                    to_lsu_packet_o.rob_idx = renamed_inst_i.rob_idx;
                    to_lsu_packet_o.lsq_idx = lsq_next_idx_i;
                    to_lsu_packet_o.addr_op_is_ready = renamed_inst_i.op1_is_ready;
                    to_lsu_packet_o.addr_op_val = renamed_inst_i.op1_data;
                    to_lsu_packet_o.addr_op_rob_tag = renamed_inst_i.op1_rob_tag;
                    to_lsu_packet_o.data_op_is_ready = renamed_inst_i.store_data_is_ready;
                    to_lsu_packet_o.data_op_val = renamed_inst_i.store_data;
                    to_lsu_packet_o.data_op_rob_tag = renamed_inst_i.store_data_rob_tag;
                end

                INSTR_BRANCH: begin
                    rob_allocate_data_o.branch_target = renamed_inst_i.pc + 4; // Simplified
                    to_branch_packet_o.opcode = renamed_inst_i.inst.opcode;
                    to_branch_packet_o.rob_idx = renamed_inst_i.rob_idx;
                    to_branch_packet_o.pc = renamed_inst_i.pc;
                    to_branch_packet_o.operand1_ready = renamed_inst_i.op1_is_ready;
                    to_branch_packet_o.operand1_val = renamed_inst_i.op1_data;
                    to_branch_packet_o.operand1_rob_tag = renamed_inst_i.op1_rob_tag;
                    to_branch_packet_o.operand2_ready = renamed_inst_i.op2_is_ready;
                    to_branch_packet_o.operand2_val = renamed_inst_i.op2_data;
                    to_branch_packet_o.operand2_rob_tag = renamed_inst_i.op2_rob_tag;
                end
            endcase
        end
    end
endmodule

