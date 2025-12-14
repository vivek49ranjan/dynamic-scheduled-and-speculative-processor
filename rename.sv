module rename_stage (
    input  logic                  clk,
    input  logic                  reset,
    
    input  logic                  decode_valid_i,
    input  decoded_instruction_t  decode_inst_i,
    input  logic [9:0]            decode_pc_i,

    input  logic [3:0]            rob_next_idx_i,

    input  logic                  commit_valid_i,
    input  rob_instruction_metadata_t commit_instr_i,
    input  logic [3:0]            commit_rob_idx_i,

    input  logic                  rename_stall_i,
    input  logic                  dispatch_can_proceed_i,

    input  logic [31:0]           reg_read_data1_i,
    input  logic [31:0]           reg_read_data2_i,

    output logic [4:0]            reg_read_addr1_o,
    output logic [4:0]            reg_read_addr2_o,

    output logic                  renamed_valid_o,
    output renamed_instruction_t  renamed_inst_o
);

    import config_pkg::*;
    import cpu_types_pkg::*;

    logic [3:0] rat [0:31];
    renamed_instruction_t renamed_inst_comb;

    logic is_load, is_store, is_alu, is_branch;
    logic [4:0] src1_reg, src2_reg, store_src_reg, dest_reg;

    logic commit_writes_reg;
    logic [4:0] commit_dest_reg;
    logic writes_reg;
    logic can_rename;

    assign is_alu    = (decode_inst_i.instr_type == INSTR_ALU);
    assign is_load   = (decode_inst_i.instr_type == INSTR_LOAD);
    assign is_store  = (decode_inst_i.instr_type == INSTR_STORE);
    assign is_branch = (decode_inst_i.instr_type == INSTR_BRANCH);

    assign src1_reg      = decode_inst_i.operand1_reg;
    assign src2_reg      = decode_inst_i.operand2_reg;
    assign store_src_reg = decode_inst_i.store_source;
    
    assign dest_reg      = is_load ? decode_inst_i.load_destination : decode_inst_i.result_reg;

    assign writes_reg = (is_alu || is_load);

    assign reg_read_addr1_o = src1_reg;
    assign reg_read_addr2_o = is_store ? store_src_reg : src2_reg;

    // Check if committing instruction writes to register
    always_comb begin
        commit_writes_reg = 1'b0;
        commit_dest_reg   = 5'b0;
        if (commit_instr_i.instr_type == INSTR_ALU || commit_instr_i.instr_type == INSTR_LOAD) begin
            commit_writes_reg = 1'b1;
            commit_dest_reg   = commit_instr_i.rd_idx;
        end
    end

    // Rename Logic
    always_comb begin
        renamed_inst_comb = '0;
        renamed_inst_comb.inst    = decode_inst_i;
        renamed_inst_comb.pc      = decode_pc_i;
        renamed_inst_comb.rob_idx = rob_next_idx_i;

        // Operand 1
        if ((rat[src1_reg] == 4'hF) || (src1_reg == 5'b0)) begin
            renamed_inst_comb.op1_is_ready = 1'b1;
            renamed_inst_comb.op1_rob_tag  = '0;
            renamed_inst_comb.op1_data     = reg_read_data1_i;
        end else begin
            renamed_inst_comb.op1_is_ready = 1'b0;
            renamed_inst_comb.op1_rob_tag  = rat[src1_reg];
            renamed_inst_comb.op1_data     = '0;
        end

        // Operand 2 (Logic for ALU vs Store)
        if (!is_store) begin
            if ((rat[src2_reg] == 4'hF) || (src2_reg == 5'b0)) begin
                renamed_inst_comb.op2_is_ready = 1'b1;
                renamed_inst_comb.op2_rob_tag  = '0;
                renamed_inst_comb.op2_data     = reg_read_data2_i;
            end else begin
                renamed_inst_comb.op2_is_ready = 1'b0;
                renamed_inst_comb.op2_rob_tag  = rat[src2_reg];
                renamed_inst_comb.op2_data     = '0;
            end
            renamed_inst_comb.store_data_is_ready = 1'b1;
        end else begin
            // For Store, op2 is irrelevant (set ready), check store_data
            renamed_inst_comb.op2_is_ready = 1'b1; 
            
            if ((rat[store_src_reg] == 4'hF) || (store_src_reg == 5'b0)) begin
                renamed_inst_comb.store_data_is_ready = 1'b1;
                renamed_inst_comb.store_data_rob_tag  = '0;
                renamed_inst_comb.store_data          = reg_read_data2_i;
            end else begin
                renamed_inst_comb.store_data_is_ready = 1'b0;
                renamed_inst_comb.store_data_rob_tag  = rat[store_src_reg];
                renamed_inst_comb.store_data          = '0;
            end
        end
    end

    assign can_rename = decode_valid_i && dispatch_can_proceed_i;

    // RAT Update Logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < 32; i++)
                rat[i] <= 4'hF; // 0xF indicates Value is in ARF (Architectural Register File)
        end else begin
            // 1. Commit Update: If committing, set RAT to 0xF IF the committing ROB tag matches current RAT
            if (commit_valid_i && commit_writes_reg) begin
                if (rat[commit_dest_reg] == commit_rob_idx_i)
                    rat[commit_dest_reg] <= 4'hF;
            end

            // 2. Dispatch/Rename Update: Overwrites commit if same cycle (Forwarding effect on RAT)
            if (can_rename && writes_reg && (dest_reg != 5'b0))
                rat[dest_reg] <= rob_next_idx_i;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            renamed_valid_o <= 1'b0;
            renamed_inst_o  <= '0;
        end else if (!rename_stall_i) begin
            renamed_valid_o <= can_rename;
            if (can_rename)
                renamed_inst_o <= renamed_inst_comb;
        end
    end
endmodule

