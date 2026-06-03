`timescale 1ns/1ps
import config_pkg::*;
import cpu_types_pkg::*;

module issue_stage (
    input  logic clk, reset,
    input  rs_status_t [7:0] alu_rs_status_i, 
    output logic [7:0] alu_rs_issue_en_o 
);

    logic [2:0] rr_ptr;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rr_ptr <= 3'd0;
        end
        else begin
            rr_ptr <= rr_ptr + 3'd1;
        end
    end

    logic add_busy;
    logic log_busy;
    logic shf_busy;
    logic cmp_busy;
    logic [2:0] idx;

    always_comb begin
        alu_rs_issue_en_o = 8'd0;
        
        add_busy = 1'b0;
        log_busy = 1'b0;
        shf_busy = 1'b0;
        cmp_busy = 1'b0;

        for (int i = 0; i < 8; i = i + 1) begin
            idx = rr_ptr + i[2:0];

            if (alu_rs_status_i[idx].valid && alu_rs_status_i[idx].ready && alu_rs_status_i[idx].fu_ready) begin
                case (alu_rs_status_i[idx].fu_type)
                    3'b000: begin
                        if (!add_busy) begin 
                            alu_rs_issue_en_o[idx] = 1'b1; 
                            add_busy = 1'b1; 
                        end
                    end
                    3'b011: begin
                        if (!log_busy) begin 
                            alu_rs_issue_en_o[idx] = 1'b1; 
                            log_busy = 1'b1; 
                        end
                    end
                    3'b100: begin
                        if (!shf_busy) begin 
                            alu_rs_issue_en_o[idx] = 1'b1; 
                            shf_busy = 1'b1; 
                        end
                    end
                    3'b111: begin
                        if (!cmp_busy) begin 
                            alu_rs_issue_en_o[idx] = 1'b1; 
                            cmp_busy = 1'b1; 
                        end
                    end
                    default: begin
                        if (!add_busy) begin 
                            alu_rs_issue_en_o[idx] = 1'b1; 
                            add_busy = 1'b1; 
                        end
                    end
                endcase
            end
        end
    end
endmodule
