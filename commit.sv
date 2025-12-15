module commit_stage (
    input  logic         clock,
    input  logic         reset,
    input  rob_entry_t   rob_head_entry_i,
    input  logic         rob_empty_i,
    input  logic         lsq_ready_to_commit_i,

    output logic         reg_write_en_o,
    output logic [4:0]   reg_write_addr_o,
    output logic [31:0]  reg_write_data_o,
    output logic         pipeline_flush_o,
    output logic [31:0]  redirect_pc_o,
    output logic         is_exception_o,
    output logic         commit_en_o,
    output logic         lsq_commit_en_o
);
    // Assume cpu_types_pkg contains core processor types like rob_entry_t, INSTR_LOAD, etc.
    import cpu_types_pkg::*; 

    logic is_load, is_store, is_branch, is_mispredict, writes_to_reg, can_commit, is_mem_op;

    // --- Instruction Classification ---
    assign is_load     = (rob_head_entry_i.inst_data.instr_type == INSTR_LOAD);
    assign is_store    = (rob_head_entry_i.inst_data.instr_type == INSTR_STORE);
    assign is_branch   = (rob_head_entry_i.inst_data.instr_type == INSTR_BRANCH);
    assign is_mem_op   = is_load || is_store;

    // Mispredict check: actual result (next PC) != predicted target
    assign is_mispredict = is_branch && (rob_head_entry_i.result_value != rob_head_entry_i.inst_data.branch_target);
    
    // Register write back only for ALU/Load, and not to R0 (5'b0)
    assign writes_to_reg = (rob_head_entry_i.inst_data.instr_type == INSTR_ALU || 
                            rob_head_entry_i.inst_data.instr_type == INSTR_LOAD) && 
                           (rob_head_entry_i.inst_data.rd_idx != 5'b0);

    // Commit requires ROB head to be complete and LSQ to be complete for memory ops
    assign can_commit = !rob_empty_i && 
                        rob_head_entry_i.is_complete && 
                        (!is_mem_op || lsq_ready_to_commit_i);

    // --- Commit Action Logic (Combinational) ---
    always_comb begin
        // Default outputs
        reg_write_en_o   = 1'b0; reg_write_addr_o = 5'b0; reg_write_data_o = 32'b0;
        pipeline_flush_o = 1'b0; redirect_pc_o    = 32'b0; is_exception_o = 1'b0;
        commit_en_o      = 1'b0; lsq_commit_en_o  = 1'b0;

        if (can_commit) begin
            commit_en_o = 1'b1; // Tell ROB to retire the instruction

            // 1. Exception Handling (Highest Priority)
            if (rob_head_entry_i.has_exception) begin
                pipeline_flush_o = 1'b1; 
                redirect_pc_o    = 32'h0000_0020; // Exception Handler PC
                is_exception_o   = 1'b1;

            // 2. Misprediction Handling
            end else if (is_mispredict) begin
                pipeline_flush_o = 1'b1; 
                redirect_pc_o    = rob_head_entry_i.result_value; // Corrected PC

            // 3. Normal Retirement
            end else begin
                // Register File Write (ALU/LOAD)
                if (writes_to_reg) begin
                    reg_write_en_o   = 1'b1; 
                    reg_write_addr_o = rob_head_entry_i.inst_data.rd_idx; 
                    reg_write_data_o = rob_head_entry_i.result_value;
                end
                
                // LSQ Retirement (LOAD/STORE)
                if (is_store || is_load) begin
                    lsq_commit_en_o = 1'b1; // Tell LSQ to retire the instruction
                end
            end
        end
    end
endmodule
