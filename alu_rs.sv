import config_pkg::*;
import cpu_types_pkg::*;

module reservation_station (
    input  logic clk, reset,
    
    input  logic rs_dispatch_valid,
    input  alu_dispatch_packet_t rs_dispatch_data,
    output logic rs_full_out,
    
    output logic [7:0]  fu_issue_opcode,
    output logic [31:0] fu_issue_operand1,
    output logic [31:0] fu_issue_operand2,
    output logic [4:0]  fu_issue_dest_reg,
    output logic [4:0]  fu_issue_rob_idx,
    output logic        fu_issue_en,
    
    input  logic        cdb_valid,
    input  logic [4:0]  cdb_rob_tag,
    input  logic [31:0] cdb_value,
    
    input  logic fu_add_sub_busy, fu_logical_busy, fu_shift_busy, fu_compare_busy
);

    parameter RS_DEPTH = 8;
    alu_rs_entry_t rs_entries[RS_DEPTH];
    
    logic [2:0] issue_idx;
    logic       can_issue;
    logic [2:0] rr_issue_ptr;
    logic [4:0] rs_allocated_idx;
    logic [3:0] busy_count;
	 logic 		 found_empty;

    always_comb begin
        busy_count = 4'd0;
        rs_allocated_idx = 5'd0;
		  found_empty = 1'b0;
        
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_entries[i].busy) begin
                busy_count = busy_count + 4'd1;
            end else begin
					 if(!found_empty) begin
						rs_allocated_idx = i[4:0];
						found_empty = 1'b1;
					end
            end
        end

        rs_full_out = (busy_count >= (RS_DEPTH - 1));
        can_issue = 1'b0;
        issue_idx = 3'd0;
        
        for (int i = 0; i < RS_DEPTH; i++) begin
            logic [2:0] idx;
            logic       op1_rdy;
            logic       op2_rdy;
            logic       fu_rdy;

            idx = rr_issue_ptr + i[2:0]; 
            
            op1_rdy = rs_entries[idx].Vj_valid || (cdb_valid && (rs_entries[idx].Qj == cdb_rob_tag));
            op2_rdy = rs_entries[idx].Vk_valid || (cdb_valid && (rs_entries[idx].Qk == cdb_rob_tag));
            
            case (rs_entries[idx].opcode[7:5])
                3'b000:  fu_rdy = !fu_add_sub_busy;
                3'b011:  fu_rdy = !fu_logical_busy;
                3'b100:  fu_rdy = !fu_shift_busy;
                3'b111:  fu_rdy = !fu_compare_busy;
                default: fu_rdy = 1'b1;
            endcase

            if (rs_entries[idx].busy && op1_rdy && op2_rdy && fu_rdy) begin
                can_issue = 1'b1;
                issue_idx = idx;
                break;
            end
        end
        
        fu_issue_en       = can_issue;
        fu_issue_opcode   = can_issue ? rs_entries[issue_idx].opcode   : 8'd0;
        fu_issue_dest_reg = can_issue ? rs_entries[issue_idx].dest_reg : 5'd0;
        fu_issue_rob_idx  = can_issue ? rs_entries[issue_idx].rob_idx  : 5'd0;
        
        if (can_issue) begin
            fu_issue_operand1 = rs_entries[issue_idx].Vj_valid ? rs_entries[issue_idx].V_j : cdb_value;
            fu_issue_operand2 = rs_entries[issue_idx].Vk_valid ? rs_entries[issue_idx].V_k : cdb_value;
        end else begin
            fu_issue_operand1 = 32'd0;
            fu_issue_operand2 = 32'd0;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rr_issue_ptr <= 3'd0;
            for (int i = 0; i < RS_DEPTH; i++) begin
                rs_entries[i].busy <= 1'b0;
            end
        end
        else begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                if (can_issue && (issue_idx == i[2:0])) begin
                    rs_entries[i].busy <= 1'b0;
                    rr_issue_ptr <= issue_idx + 3'd1;
                end
					 
                if (rs_dispatch_valid && !rs_entries[i].busy && (rs_allocated_idx[2:0] == i[2:0])) begin
                    rs_entries[i].busy     <= 1'b1;
                    rs_entries[i].opcode   <= rs_dispatch_data.opcode;
                    rs_entries[i].rob_idx  <= rs_dispatch_data.rob_idx;
                    rs_entries[i].dest_reg <= rs_dispatch_data.dest_reg;
                    
                    if (cdb_valid && (rs_dispatch_data.op1_rob_tag == cdb_rob_tag)) begin
                        rs_entries[i].Vj_valid <= 1'b1;
                        rs_entries[i].V_j      <= cdb_value;
                    end else begin
                        rs_entries[i].Vj_valid <= rs_dispatch_data.op1_is_ready;
                        rs_entries[i].V_j      <= rs_dispatch_data.op1_val;
                        rs_entries[i].Qj       <= rs_dispatch_data.op1_rob_tag;
                    end

                    if (cdb_valid && (rs_dispatch_data.op2_rob_tag == cdb_rob_tag)) begin
                        rs_entries[i].Vk_valid <= 1'b1;
                        rs_entries[i].V_k      <= cdb_value;
                    end else begin
                        rs_entries[i].Vk_valid <= rs_dispatch_data.op2_is_ready;
                        rs_entries[i].V_k      <= rs_dispatch_data.op2_val;
                        rs_entries[i].Qk       <= rs_dispatch_data.op2_rob_tag;
                    end
                end 
					 
                else if (rs_entries[i].busy && cdb_valid) begin
                    if (!rs_entries[i].Vj_valid && (rs_entries[i].Qj == cdb_rob_tag)) begin
                        rs_entries[i].Vj_valid <= 1'b1;
                        rs_entries[i].V_j      <= cdb_value;
                    end
                    if (!rs_entries[i].Vk_valid && (rs_entries[i].Qk == cdb_rob_tag)) begin
                        rs_entries[i].Vk_valid <= 1'b1;
                        rs_entries[i].V_k      <= cdb_value;
                    end
                end
            end 
        end 
    end 
endmodule
