
module issue_stage (
    input clk,
    input reset,
    input rs_status_t [7:0] alu_rs_status_i, 
    output logic [7:0] alu_rs_issue_en_o 
);
    import cpu_types_pkg::*;
    import config_pkg::*;
    
    logic       best_candidate_valid;
    logic [3:0] best_candidate_rob_idx;
    logic [2:0] best_candidate_rs_idx; 

    always_comb begin
        best_candidate_valid   = 1'b0;
        best_candidate_rob_idx = 4'hF;
        best_candidate_rs_idx  = '0;
        
        // Find Oldest Ready Instruction (Smallest ROB ID implies oldest in circular buffer roughly)
        // Note: Ideal logic requires circular age comparison, using direct compare for simplicity.
        for (int i = 0; i < 8; i++) begin 
            if (alu_rs_status_i[i].valid && alu_rs_status_i[i].ready && alu_rs_status_i[i].fu_ready) begin
                // Simple greedy: take the first one found or minimize rob_idx
                if (!best_candidate_valid || (alu_rs_status_i[i].rob_idx < best_candidate_rob_idx)) begin
                    best_candidate_valid   = 1'b1;
                    best_candidate_rob_idx = alu_rs_status_i[i].rob_idx;
                    best_candidate_rs_idx  = i[2:0];
                end
            end
        end

        alu_rs_issue_en_o = 8'b0; 
        if (best_candidate_valid) begin
            alu_rs_issue_en_o[best_candidate_rs_idx] = 1'b1;
        end
    end
endmodule