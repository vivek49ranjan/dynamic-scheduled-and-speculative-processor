import cpu_types_pkg::*;
import config_pkg::*;

module rob (
    input  logic        clk, reset,
    input  logic        pipeline_flush_i, 
    input  logic        rob_allocate_valid_i,
    input  rob_instruction_metadata_t rob_allocate_data_i,
    input  logic        wb_valid_i,
    input  logic [4:0]  wb_rob_tag_i,
    input  logic [31:0] wb_result_val_i, 
    input  logic        commit_ready_i, 
    input  logic        wb_branch_mispredict_i, 

    output logic        rob_full_o,
    output logic [4:0]  rob_next_idx_o,
    output logic        commit_valid_o,
    output rob_entry_t  commit_data_o,
    output logic [4:0]  head_ptr_o,
    output logic        flush_o,
    output logic [31:0] flush_pc_o,
    output logic [9:0]  flush_branch_pc_o 
);

    rob_entry_t rob_file [0:31]; 
    logic [4:0] head_ptr, tail_ptr;
    logic [5:0] count; 

    assign head_ptr_o     = head_ptr;
    assign rob_next_idx_o = tail_ptr;
    assign rob_full_o     = (count >= 6'd32);

    assign commit_valid_o = (count != 0) && rob_file[head_ptr].busy && rob_file[head_ptr].is_complete;
    assign commit_data_o  = rob_file[head_ptr];
    
    assign flush_o           = commit_valid_o && commit_ready_i && commit_data_o.inst_data.is_mispredicted;
    assign flush_pc_o        = commit_data_o.result_value; 
    assign flush_branch_pc_o = commit_data_o.inst_data.pc[9:0];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            head_ptr <= 5'd0;
            tail_ptr <= 5'd0;
            count    <= 6'd0;
            for (int i = 0; i < 32; i++) begin
                rob_file[i].busy <= 1'b0;
                rob_file[i].is_complete <= 1'b0;
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
            if (wb_valid_i && rob_file[wb_rob_tag_i].busy) begin
                rob_file[wb_rob_tag_i].is_complete  <= 1'b1;
                rob_file[wb_rob_tag_i].result_value <= wb_result_val_i;
                rob_file[wb_rob_tag_i].inst_data.is_mispredicted <= wb_branch_mispredict_i;
            end

            case ({ (rob_allocate_valid_i && !rob_full_o), (commit_valid_o && commit_ready_i) })
                2'b10: begin 
                    rob_file[tail_ptr].busy        <= 1'b1;
                    rob_file[tail_ptr].is_complete <= 1'b0;
                    rob_file[tail_ptr].inst_data   <= rob_allocate_data_i;
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
                    rob_file[tail_ptr].inst_data   <= rob_allocate_data_i;
                    tail_ptr <= tail_ptr + 5'd1;
                    
                    rob_file[head_ptr].busy        <= 1'b0;
                    head_ptr <= head_ptr + 5'd1;
                end
                default: ;
            endcase
        end
    end
endmodule
