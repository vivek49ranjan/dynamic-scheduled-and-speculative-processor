module rob (
    input  logic        clk,
    input  logic        reset,
    input  logic        pipeline_flush_i,

    input  logic        rob_allocate_valid_i,
    input  rob_instruction_metadata_t rob_allocate_data_i,
    input  logic [3:0]  rob_allocate_rob_idx_i,

    input  logic        wb_valid_i,
    input  logic [3:0]  wb_rob_tag_i,
    input  logic [31:0] wb_result_val_i,
    input  logic        wb_has_exception_i,

    input  logic        commit_ready_i,

    output logic        rob_full_o,
    output logic [3:0]  rob_next_idx_o,
    
    output logic        commit_valid_o,
    output rob_entry_t  commit_data_o,
    
    output logic        flush_o,
    output logic [31:0] flush_pc_o
);
    import cpu_types_pkg::*;
    import config_pkg::*;

    rob_entry_t rob_file [0:15];
    logic [3:0] head_ptr;
    logic [3:0] tail_ptr;
    logic [4:0] entry_count;

    logic do_allocate;
    logic do_commit;
    rob_entry_t head_entry;

    assign rob_full_o     = (entry_count == 16);
    assign rob_next_idx_o = tail_ptr;
    assign head_entry     = rob_file[head_ptr];

    assign commit_valid_o = head_entry.busy && head_entry.is_complete && (entry_count != 0);
    assign commit_data_o  = head_entry;

    assign do_allocate = rob_allocate_valid_i && !rob_full_o;
    assign do_commit   = commit_valid_o && commit_ready_i;

    // Flush Logic
    assign flush_o = do_commit && (
        (head_entry.inst_data.instr_type == INSTR_BRANCH && 
         head_entry.result_value != head_entry.inst_data.branch_target) ||
        head_entry.has_exception
    );

    assign flush_pc_o = (head_entry.inst_data.instr_type == INSTR_BRANCH) ? 
                         head_entry.inst_data.branch_target : 32'h0000_0000;

    integer i;
    
    // --- FIX: Separated Async Reset from Sync Flush ---
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // 1. Asynchronous Reset (Hardware Reset)
            head_ptr    <= 4'b0;
            tail_ptr    <= 4'b0;
            entry_count <= 5'b0;
            for (i = 0; i < 16; i++) begin
                rob_file[i].busy <= 1'b0;
                rob_file[i].is_complete <= 1'b0;
                rob_file[i].has_exception <= 1'b0;
                rob_file[i].inst_data <= '0;
                rob_file[i].result_value <= '0;
            end
        end else if (pipeline_flush_i || flush_o) begin
            // 2. Synchronous Flush (Exception/Mispredict)
            head_ptr    <= 4'b0;
            tail_ptr    <= 4'b0;
            entry_count <= 5'b0;
            for (i = 0; i < 16; i++) begin
                rob_file[i].busy <= 1'b0;
                rob_file[i].is_complete <= 1'b0;
                rob_file[i].has_exception <= 1'b0;
            end
        end else begin
            // 3. Normal Operation
            
            // Allocation
            if (do_allocate) begin
                rob_file[rob_allocate_rob_idx_i].busy          <= 1'b1;
                rob_file[rob_allocate_rob_idx_i].is_complete   <= 1'b0;
                rob_file[rob_allocate_rob_idx_i].has_exception <= 1'b0;
                rob_file[rob_allocate_rob_idx_i].inst_data     <= rob_allocate_data_i;
                rob_file[rob_allocate_rob_idx_i].result_value  <= 32'b0;
                tail_ptr <= tail_ptr + 1'b1;
            end

            // Writeback (Common Data Bus)
            if (wb_valid_i && rob_file[wb_rob_tag_i].busy) begin
                rob_file[wb_rob_tag_i].is_complete   <= 1'b1;
                rob_file[wb_rob_tag_i].result_value  <= wb_result_val_i;
                rob_file[wb_rob_tag_i].has_exception <= wb_has_exception_i;
            end

            // Commit
            if (do_commit) begin
                rob_file[head_ptr].busy <= 1'b0;
                head_ptr <= head_ptr + 1'b1;
            end

            // Count Update
            case ({do_allocate, do_commit})
                2'b10: entry_count <= entry_count + 1'b1;
                2'b01: entry_count <= entry_count - 1'b1;
                default: entry_count <= entry_count;
            endcase
        end
    end
endmodule