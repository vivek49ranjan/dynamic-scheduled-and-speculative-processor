import cpu_types_pkg::*;
import config_pkg::*;

module rename_stage (
    input  logic clk, reset, flush_i,
    input  logic id_valid_i,
    input  decoded_instruction_t decode_inst_i,
    input  logic [9:0] decode_pc_i,
    input  logic [4:0] rob_next_idx_i,
    
    input  logic commit_valid_i,
    input  rob_instruction_metadata_t commit_instr_i,
    input  logic [4:0] commit_rob_idx_i,
    input  logic rename_stall_i,
    input  logic dispatch_success_i, 

    output logic renamed_valid_o,
    output renamed_instruction_t renamed_inst_o,
    output logic rename_busy_o
);

    logic [5:0] rat [0:31]; 
    localparam READY_BIT = 5;
    localparam ARCH_STATE = 6'b100000;

  
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < 32; i++) begin
                rat[i] <= ARCH_STATE;
            end
        end else begin
            if (flush_i) begin
                for (int i = 0; i < 32; i++) begin
                    rat[i] <= ARCH_STATE;
                end
            end else begin
                for (int i = 1; i < 32; i++) begin
                    
                    if (commit_valid_i && (commit_instr_i.rd_idx == i[4:0])) begin
                        if (rat[i][4:0] == commit_rob_idx_i) begin
                            rat[i] <= ARCH_STATE;
                        end
                    end

                    if (id_valid_i && dispatch_success_i && (decode_inst_i.result_reg == i[4:0])) begin
                        rat[i] <= {1'b0, rob_next_idx_i};
                    end
                end
            end
        end
    end

    always_comb begin
        logic [5:0] op1_lkp, op2_lkp;
        
        renamed_valid_o = id_valid_i && !flush_i && !rename_stall_i;
        rename_busy_o   = rename_stall_i;

        op1_lkp = rat[decode_inst_i.operand1_reg];
        op2_lkp = rat[decode_inst_i.operand2_reg];

        if (commit_valid_i && commit_instr_i.rd_idx != 0) begin
            if (decode_inst_i.operand1_reg == commit_instr_i.rd_idx && op1_lkp[4:0] == commit_rob_idx_i)
                op1_lkp = ARCH_STATE;
            if (decode_inst_i.operand2_reg == commit_instr_i.rd_idx && op2_lkp[4:0] == commit_rob_idx_i)
                op2_lkp = ARCH_STATE;
        end

        renamed_inst_o = '0;
        renamed_inst_o.inst         = decode_inst_i;
        renamed_inst_o.rob_idx      = rob_next_idx_i;
        renamed_inst_o.pc           = decode_pc_i;
        renamed_inst_o.op1_is_ready = op1_lkp[READY_BIT];
        renamed_inst_o.op1_rob_tag  = op1_lkp[4:0];
        renamed_inst_o.op2_is_ready = op2_lkp[READY_BIT];
        renamed_inst_o.op2_rob_tag  = op2_lkp[4:0];
    end
endmodule
