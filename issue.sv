import cpu_types_pkg::*;
import config_pkg::*;

module issue_stage (
    input  logic clk, reset,
    input  rs_status_t [7:0] alu_rs_status_i, 
    output logic [7:0] alu_rs_issue_en_o 
);

    logic [2:0] rr_ptr;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rr_ptr <= 3'd0;
        end else if (|alu_rs_issue_en_o) begin
            rr_ptr <= rr_ptr + 3'd1;
        end
    end

    always_comb begin
        alu_rs_issue_en_o = 8'b0;
        
        for (int i = 0; i < 8; i++) begin
            automatic logic [2:0] idx = rr_ptr + i[2:0];
            
            if (alu_rs_status_i[idx].valid && 
                alu_rs_status_i[idx].ready && 
                alu_rs_status_i[idx].fu_ready) begin
                
                alu_rs_issue_en_o[idx] = 1'b1;
                break; 
            end
        end
    end
endmodule
