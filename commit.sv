import cpu_types_pkg::*;

module commit_stage (
    input  logic               clock, reset,
    input  rob_entry_t         rob_head_entry_i,
    input  logic               rob_empty_i,     
    input  logic               lsq_ready_to_commit_i,
    
    output logic               reg_write_en_o,
    output logic [4:0]         reg_write_addr_o,
    output logic [31:0]        reg_write_data_o,
    output logic               commit_en_o    
);

    always_comb begin
        reg_write_en_o   = 1'b0;
        reg_write_addr_o = 5'd0;
        reg_write_data_o = 32'd0;
        commit_en_o      = 1'b0;

        if (!rob_empty_i && rob_head_entry_i.busy && rob_head_entry_i.is_complete) begin
            
            if (rob_head_entry_i.inst_data.instr_type == INSTR_ALU || 
                rob_head_entry_i.inst_data.instr_type == INSTR_LOAD) begin
                
                if (rob_head_entry_i.inst_data.rd_idx != 5'd0) begin
                    reg_write_en_o   = 1'b1;
                    reg_write_addr_o = rob_head_entry_i.inst_data.rd_idx;
                    reg_write_data_o = rob_head_entry_i.result_value;
                end
            end

            if (rob_head_entry_i.inst_data.instr_type == INSTR_STORE) begin
                if (lsq_ready_to_commit_i) commit_en_o = 1'b1;
            end else begin
                commit_en_o = 1'b1;
            end
        end
    end
endmodule
