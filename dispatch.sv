import config_pkg::*;
import cpu_types_pkg::*;

module dispatch_stage (
    input  logic clk, reset, flush_i,
    
    input  logic                 rn_valid_i,
    input  renamed_instruction_t rn_inst_i,
    
    output logic                 dispatch_stall_o,
    
    output logic [4:0]  rf_raddr1_o, rf_raddr2_o,
    input  logic [31:0] rf_rdata1_i, rf_rdata2_i,
    
    input  logic        commit_wen_i,
    input  logic [4:0]  commit_waddr_i,
    input  logic [31:0] commit_wdata_i,
    
    input  logic        cdb_valid_i,
    input  logic [4:0]  cdb_tag_i,
    input  logic [31:0] cdb_val_i,

    output logic [4:0]  rob_read_idx1_o,
    input  logic        rob_read_ready1_i,
    input  logic        rob_read_busy1_i,
    input  logic [31:0] rob_read_val1_i,
    
    output logic [4:0]  rob_read_idx2_o,
    input  logic        rob_read_ready2_i,
    input  logic        rob_read_busy2_i,
    input  logic [31:0] rob_read_val2_i,

    input  logic alu_rs_full_i, 
    input  logic lsq_rs_full_i, 
    input  logic branch_rs_full_i,
    
    output logic                 rob_fill_valid_o,
    output logic [4:0]           rob_fill_idx_o,
    output rob_instruction_metadata_t rob_fill_data_o,
    
    output logic                    to_alu_valid_o,
    output alu_dispatch_packet_t    to_alu_packet_o,
    output logic                    to_lsu_valid_o,
    output lsu_dispatch_packet_t    to_lsu_packet_o,
    output logic                    to_branch_valid_o,
    output branch_dispatch_packet_t to_branch_packet_o
);

    logic [31:0] sign_extended_imm;
    logic        is_alu_imm;
    logic        rs_has_space;
    logic        dispatch_fire;

    assign sign_extended_imm = rn_inst_i.inst.immediate;
    
   
    assign is_alu_imm = (rn_inst_i.inst.instr_type == INSTR_ALU) && (rn_inst_i.inst.operand2_reg == 5'd0);

    assign rf_raddr1_o = rn_inst_i.inst.operand1_reg;
    assign rf_raddr2_o = (rn_inst_i.inst.instr_type == INSTR_STORE) ? 
                          rn_inst_i.inst.store_source : rn_inst_i.inst.operand2_reg;

    assign rob_read_idx1_o = rn_inst_i.op1_rob_tag;
    assign rob_read_idx2_o = rn_inst_i.op2_rob_tag;

    logic [31:0] op1_val_resolved;
    logic        op1_ready_resolved;
    logic [31:0] op2_val_resolved;
    logic        op2_ready_resolved;

    always_comb begin
        if (rn_inst_i.op1_is_ready) begin
            op1_val_resolved   = rf_rdata1_i;
            op1_ready_resolved = 1'b1;
        end else if (commit_wen_i && commit_waddr_i == rf_raddr1_o && rf_raddr1_o != 0) begin
            op1_val_resolved   = commit_wdata_i;
            op1_ready_resolved = 1'b1;
        end else if (cdb_valid_i && cdb_tag_i == rn_inst_i.op1_rob_tag) begin
            op1_val_resolved   = cdb_val_i;
            op1_ready_resolved = 1'b1;
        end else if (!rob_read_busy1_i) begin
            op1_val_resolved   = rf_rdata1_i;
            op1_ready_resolved = 1'b1;
        end else if (rob_read_ready1_i) begin
            op1_val_resolved   = rob_read_val1_i;
            op1_ready_resolved = 1'b1;
        end else begin
            op1_val_resolved   = rf_rdata1_i; 
            op1_ready_resolved = 1'b0;
        end

        if (is_alu_imm) begin
            op2_val_resolved   = sign_extended_imm;
            op2_ready_resolved = 1'b1;
        end else if (rn_inst_i.op2_is_ready) begin
            op2_val_resolved   = rf_rdata2_i;
            op2_ready_resolved = 1'b1;
        end else if (commit_wen_i && commit_waddr_i == rf_raddr2_o && rf_raddr2_o != 0) begin
            op2_val_resolved   = commit_wdata_i;
            op2_ready_resolved = 1'b1;
        end else if (cdb_valid_i && cdb_tag_i == rn_inst_i.op2_rob_tag) begin
            op2_val_resolved   = cdb_val_i;
            op2_ready_resolved = 1'b1;
        end else if (!rob_read_busy2_i) begin
            op2_val_resolved   = rf_rdata2_i;
            op2_ready_resolved = 1'b1;
        end else if (rob_read_ready2_i) begin
            op2_val_resolved   = rob_read_val2_i;
            op2_ready_resolved = 1'b1;
        end else begin
            op2_val_resolved   = rf_rdata2_i;
            op2_ready_resolved = 1'b0;
        end
    end

    always_comb begin
        case (rn_inst_i.inst.instr_type)
            INSTR_ALU:    rs_has_space = !alu_rs_full_i;
            INSTR_LOAD,
            INSTR_STORE:  rs_has_space = !lsq_rs_full_i;
            INSTR_BRANCH: rs_has_space = !branch_rs_full_i;
            default:      rs_has_space = 1'b1;
        endcase

        dispatch_stall_o = rn_valid_i && !rs_has_space;
        dispatch_fire    = rn_valid_i && !dispatch_stall_o && !flush_i;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rob_fill_valid_o  <= 1'b0;
            rob_fill_data_o   <= '0;
            rob_fill_idx_o    <= '0;
            {to_alu_valid_o, to_lsu_valid_o, to_branch_valid_o}    <= '0;
            {to_alu_packet_o, to_lsu_packet_o, to_branch_packet_o} <= '0;
        end else if (flush_i) begin
            rob_fill_valid_o  <= 1'b0;
            {to_alu_valid_o, to_lsu_valid_o, to_branch_valid_o}    <= '0;
        end else begin
            rob_fill_valid_o  <= 1'b0;
            to_alu_valid_o    <= 1'b0;
            to_lsu_valid_o    <= 1'b0;
            to_branch_valid_o <= 1'b0;

            if (dispatch_fire) begin
                rob_fill_valid_o           <= 1'b1;
                rob_fill_idx_o             <= rn_inst_i.rob_idx; 
                
                rob_fill_data_o.pc         <= {22'b0, rn_inst_i.pc};
                rob_fill_data_o.opcode     <= rn_inst_i.inst.opcode;
                rob_fill_data_o.instr_type <= rn_inst_i.inst.instr_type;
                rob_fill_data_o.rd_idx     <= rn_inst_i.inst.result_reg;
                // REMOVED lsq_idx assignment from here

                case (rn_inst_i.inst.instr_type)
                    INSTR_ALU: begin
                        to_alu_valid_o               <= 1'b1;
                        to_alu_packet_o.opcode       <= rn_inst_i.inst.opcode;
                        to_alu_packet_o.rob_idx      <= rn_inst_i.rob_idx;
                        to_alu_packet_o.dest_reg     <= rn_inst_i.inst.result_reg;
                        to_alu_packet_o.op1_val      <= op1_val_resolved;
                        to_alu_packet_o.op1_is_ready <= op1_ready_resolved;
                        to_alu_packet_o.op1_rob_tag  <= rn_inst_i.op1_rob_tag;
                        to_alu_packet_o.op2_val      <= op2_val_resolved;
                        to_alu_packet_o.op2_is_ready <= op2_ready_resolved;
                        to_alu_packet_o.op2_rob_tag  <= (is_alu_imm) ? 5'h0 : rn_inst_i.op2_rob_tag;
                    end

                    INSTR_LOAD, INSTR_STORE: begin
                        to_lsu_valid_o                   <= 1'b1;
                        to_lsu_packet_o.opcode           <= rn_inst_i.inst.opcode;
                        to_lsu_packet_o.immediate        <= sign_extended_imm; 
                        to_lsu_packet_o.rob_idx          <= rn_inst_i.rob_idx;
                        to_lsu_packet_o.dest_reg         <= rn_inst_i.inst.result_reg;
                        to_lsu_packet_o.addr_op_val      <= op1_val_resolved;
                        to_lsu_packet_o.addr_op_is_ready <= op1_ready_resolved;
                        to_lsu_packet_o.addr_op_rob_tag  <= rn_inst_i.op1_rob_tag;
                        to_lsu_packet_o.data_op_val      <= op2_val_resolved;
                        to_lsu_packet_o.data_op_is_ready <= op2_ready_resolved;
                        to_lsu_packet_o.data_op_rob_tag  <= rn_inst_i.op2_rob_tag;
                    end

                    INSTR_BRANCH: begin
                        to_branch_valid_o                   <= 1'b1;
                        to_branch_packet_o.opcode           <= rn_inst_i.inst.opcode;
                        to_branch_packet_o.rob_idx          <= rn_inst_i.rob_idx;
                        to_branch_packet_o.pc               <= {22'b0, rn_inst_i.pc};
                        to_branch_packet_o.immediate        <= sign_extended_imm; 
                        to_branch_packet_o.operand1_val     <= op1_val_resolved;
                        to_branch_packet_o.operand1_ready   <= op1_ready_resolved;
                        to_branch_packet_o.operand1_rob_tag <= rn_inst_i.op1_rob_tag;
                        to_branch_packet_o.operand2_val     <= op2_val_resolved;
                        to_branch_packet_o.operand2_ready   <= op2_ready_resolved;
                        to_branch_packet_o.operand2_rob_tag <= rn_inst_i.op2_rob_tag;
                        
                        to_branch_packet_o.predicted_taken  <= rn_inst_i.inst.predicted_taken;
                        to_branch_packet_o.predicted_target <= rn_inst_i.inst.predicted_target;
                    end
                    
                    default: ;
                endcase
            end
        end
    end
endmodule
