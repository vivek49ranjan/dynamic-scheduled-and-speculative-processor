import cpu_types_pkg::*;
import config_pkg::*;

module rob (
    input  logic        clk, reset,
    input  logic        pipeline_flush_i, 
    
    input  logic        rob_alloc_valid_i,
    output logic        rob_full_o,
    output logic [4:0]  rob_alloc_idx_o,
    
    input  logic        rob_fill_valid_i,
    input  logic [4:0]  rob_fill_idx_i,
    input  rob_instruction_metadata_t rob_fill_data_i,
    
    input  logic        cdb_valid_i,
    input  logic [4:0]  cdb_rob_tag_i,
    input  logic [31:0] cdb_result_val_i, 
    input  logic [9:0]  cdb_target_pc_i, 
    input  logic        cdb_branch_mispredict_i, 
    
    input  logic        commit_ready_i, 
    output logic        commit_valid_o,
    output rob_entry_t  commit_data_o,
     
    output logic [4:0]  head_ptr_o,
     
    output logic        flush_o,
    output logic [9:0] flush_pc_o,
    output logic [9:0]  flush_branch_pc_o,

    input  logic [4:0]  read_idx1_i,
    output logic        read_ready1_o,
    output logic        read_busy1_o,
    output logic [31:0] read_val1_o,
    
    input  logic [4:0]  read_idx2_i,
    output logic        read_ready2_o,
    output logic        read_busy2_o,
    output logic [31:0] read_val2_o
);

    rob_entry_t rob_file [0:31]; 
    logic [9:0] rob_branch_targets [0:31]; 
    
    logic [4:0] head_ptr, tail_ptr;
    logic [5:0] count; 

    logic is_bogus_branch;
    
    assign is_bogus_branch = commit_data_o.inst_data.pred_taken && 
                         (commit_data_o.inst_data.instr_type != INSTR_BRANCH) ;
                         

    assign head_ptr_o      = head_ptr;
    assign rob_alloc_idx_o = tail_ptr; 
    assign rob_full_o      = (count >= 6'd31);

    assign commit_valid_o  = (count != 0) && rob_file[head_ptr].busy && rob_file[head_ptr].is_complete;
    assign commit_data_o   = rob_file[head_ptr];
    
    assign flush_o           = commit_valid_o && commit_ready_i && 
                               (commit_data_o.inst_data.is_mispredicted || is_bogus_branch);
                               
    assign flush_pc_o        = is_bogus_branch ? commit_data_o.inst_data.pc[9:0] + 10'd1
                                               : rob_branch_targets[head_ptr];
                                               
    assign flush_branch_pc_o = commit_data_o.inst_data.pc[9:0];

    assign read_ready1_o = rob_file[read_idx1_i].is_complete;
    assign read_busy1_o  = rob_file[read_idx1_i].busy;
    assign read_val1_o   = rob_file[read_idx1_i].result_value;

    assign read_ready2_o = rob_file[read_idx2_i].is_complete;
    assign read_busy2_o  = rob_file[read_idx2_i].busy;
    assign read_val2_o   = rob_file[read_idx2_i].result_value;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            head_ptr <= 5'd0;
            tail_ptr <= 5'd0;
            count    <= 6'd0;
            for (int i = 0; i < 32; i++) begin
                rob_file[i].busy <= 1'b0;
                rob_file[i].is_complete <= 1'b0;
                rob_branch_targets[i] <= 10'd0;
            end
        end else if (pipeline_flush_i || (flush_o && commit_ready_i)) begin
            head_ptr <= 5'd0;
            tail_ptr <= 5'd0;
            count    <= 6'd0;
            for (int i = 0; i < 32; i++) begin
                rob_file[i].busy <= 1'b0;
                rob_file[i].is_complete <= 1'b0;
            end
        end else begin
            if (cdb_valid_i && rob_file[cdb_rob_tag_i].busy) begin
                rob_file[cdb_rob_tag_i].is_complete  <= 1'b1;
                rob_file[cdb_rob_tag_i].result_value <= cdb_result_val_i;
                rob_file[cdb_rob_tag_i].inst_data.is_mispredicted <= cdb_branch_mispredict_i;
                rob_branch_targets[cdb_rob_tag_i]    <= cdb_target_pc_i; 
            end

            if (rob_fill_valid_i) begin
                rob_file[rob_fill_idx_i].inst_data <= rob_fill_data_i;
            end

            case ({ (rob_alloc_valid_i && !rob_full_o), (commit_valid_o && commit_ready_i) })
                2'b10: begin 
                    rob_file[tail_ptr].busy        <= 1'b1;
                    rob_file[tail_ptr].is_complete <= 1'b0;
                    tail_ptr <= tail_ptr + 5'd1;
                    count    <= count + 6'd1;
                end
                2'b01: begin 
                    rob_file[head_ptr].busy <= 1'b0; 
                    head_ptr <= head_ptr + 5'd1;
                    count    <= count - 6'd1;
                end
                2'b11: begin 
                    rob_file[tail_ptr].busy        <= 1'b1;
                    rob_file[tail_ptr].is_complete <= 1'b0;
                    tail_ptr <= tail_ptr + 5'd1;
                    
                    rob_file[head_ptr].busy        <= 1'b0;
                    head_ptr <= head_ptr + 5'd1;
                end
                default: ;
            endcase
        end
    end
endmodule
