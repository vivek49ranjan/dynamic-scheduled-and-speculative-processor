import cpu_types_pkg::*;
import config_pkg::*;

module rename_stage (
    input  logic clk, reset, flush_i,
    input  logic id_valid_i,
    input  decoded_instruction_t decode_inst_i,
    input  logic [9:0] decode_pc_i,
    
    input  logic [4:0] rob_alloc_idx_i,
    input  logic rob_full_i,
    output logic rob_alloc_valid_o,
    
    input  logic commit_valid_i,
    input  rob_instruction_metadata_t commit_instr_i,
    input  logic [4:0] commit_rob_idx_i,
    
    input  logic dispatch_stall_i,
    
    output logic                 rn_valid_o,
    output renamed_instruction_t rn_inst_o,
    output logic rename_stall_o 
);

    logic [5:0] rat [0:31]; 
    localparam READY_BIT = 5;
    localparam ARCH_STATE = 6'b100000;

    logic rename_fire;

    assign rename_stall_o = rob_full_i || dispatch_stall_i;
    assign rename_fire    = id_valid_i && !rename_stall_o && !flush_i;
    assign rob_alloc_valid_o = rename_fire;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rn_valid_o <= 1'b0;
            rn_inst_o  <= '0;
            for (int i = 0; i < 32; i++) begin
                rat[i] <= ARCH_STATE;
            end
        end else if (flush_i) begin
            rn_valid_o <= 1'b0;
            for (int i = 0; i < 32; i++) begin
                rat[i] <= ARCH_STATE;
            end
        end else begin
            if (!dispatch_stall_i) begin
                rn_valid_o <= rename_fire;
                if (rename_fire) begin
                    rn_inst_o.inst         <= decode_inst_i;
                    rn_inst_o.rob_idx      <= rob_alloc_idx_i;
                    rn_inst_o.pc           <= decode_pc_i;
                    
                    if (commit_valid_i && commit_instr_i.rd_idx != 0 &&
                        decode_inst_i.operand1_reg == commit_instr_i.rd_idx && 
                        rat[decode_inst_i.operand1_reg][4:0] == commit_rob_idx_i) begin
                        rn_inst_o.op1_is_ready <= ARCH_STATE[READY_BIT];
                        rn_inst_o.op1_rob_tag  <= ARCH_STATE[4:0];
                    end else begin
                        rn_inst_o.op1_is_ready <= rat[decode_inst_i.operand1_reg][READY_BIT];
                        rn_inst_o.op1_rob_tag  <= rat[decode_inst_i.operand1_reg][4:0];
                    end

                    if (commit_valid_i && commit_instr_i.rd_idx != 0 &&
                        decode_inst_i.operand2_reg == commit_instr_i.rd_idx && 
                        rat[decode_inst_i.operand2_reg][4:0] == commit_rob_idx_i) begin
                        rn_inst_o.op2_is_ready <= ARCH_STATE[READY_BIT];
                        rn_inst_o.op2_rob_tag  <= ARCH_STATE[4:0];
                    end else begin
                        rn_inst_o.op2_is_ready <= rat[decode_inst_i.operand2_reg][READY_BIT];
                        rn_inst_o.op2_rob_tag  <= rat[decode_inst_i.operand2_reg][4:0];
                    end
                end
            end

            for (int i = 1; i < 32; i++) begin
                if (commit_valid_i && (commit_instr_i.rd_idx == i[4:0])) begin
                    if (rat[i][4:0] == commit_rob_idx_i) begin
                        rat[i] <= ARCH_STATE;
                    end
                end

                if (rename_fire && (decode_inst_i.result_reg == i[4:0])) begin
                    rat[i] <= {1'b0, rob_alloc_idx_i};
                end
            end
        end
    end
endmodule
