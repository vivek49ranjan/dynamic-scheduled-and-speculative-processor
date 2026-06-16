import config_pkg::*;
import cpu_types_pkg::*;

module branch_reservation_station (
    input  logic clock, reset,
    input  logic rs_dispatch_valid,
    input  branch_dispatch_packet_t rs_dispatch_data,
    output logic rs_full_out,
    
    output logic fu_issue_en,
    output logic [7:0]  fu_issue_opcode,
    output logic [31:0] fu_issue_operand1,
    output logic [31:0] fu_issue_operand2,
    output logic [31:0] fu_issue_pc,     
    output logic [31:0] fu_issue_imm,   
    output logic [4:0]  fu_issue_rob_idx,
    output logic        fu_issue_pred_taken,   
    output logic [9:0]  fu_issue_pred_target,  
    
    input  logic cdb_valid,
    input  logic [4:0]  cdb_rob_tag,
    input  logic [31:0] cdb_value
);

    parameter RS_DEPTH = 4;
    branch_rs_entry_t rs_entries[RS_DEPTH];
    
    logic [4:0] issue_idx;
    logic       can_issue;
    logic [1:0] rs_allocated_idx;
    logic [1:0] rr_issue_ptr; 
    
    logic [2:0] busy_count;
    logic       found_empty;

    always_comb begin
        busy_count = 3'd0;
        rs_allocated_idx = 2'd0;
        found_empty = 1'b0;
        
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_entries[i].busy) begin
                busy_count = busy_count + 3'd1;
            end else begin
                if (!found_empty) begin
                    rs_allocated_idx = i[4:0];
                    found_empty = 1'b1;
                end
            end
        end

        rs_full_out = (busy_count >= (RS_DEPTH - 1));
        can_issue = 1'b0;
        issue_idx = 5'd0;
        
        for (int i = 0; i < RS_DEPTH; i++) begin
            logic [1:0] idx;
            logic       op1_rdy;
            logic       op2_rdy;

            idx = rr_issue_ptr + i[1:0]; 
            op1_rdy = rs_entries[idx].Vj_ready || (cdb_valid && (rs_entries[idx].Qj == cdb_rob_tag) && !rs_entries[idx].Vj_ready);
            op2_rdy = rs_entries[idx].Vk_ready || (cdb_valid && (rs_entries[idx].Qk == cdb_rob_tag) && !rs_entries[idx].Vk_ready);
            
            if (rs_entries[idx].busy && op1_rdy && op2_rdy) begin
                can_issue = 1'b1;
                issue_idx = {3'b000, idx};
                break;
            end
        end
        
        fu_issue_en          = can_issue;
        fu_issue_opcode      = can_issue ? rs_entries[issue_idx[1:0]].opcode        : 8'h0;
        fu_issue_pc          = can_issue ? rs_entries[issue_idx[1:0]].pc            : 32'h0;
        fu_issue_imm         = can_issue ? rs_entries[issue_idx[1:0]].imm           : 32'h0;
        fu_issue_rob_idx     = can_issue ? rs_entries[issue_idx[1:0]].rob_idx       : 5'h0;
        fu_issue_pred_taken  = can_issue ? rs_entries[issue_idx[1:0]].pred_taken    : 1'b0; 
        fu_issue_pred_target = can_issue ? rs_entries[issue_idx[1:0]].pred_target   : 10'h0; 

        if (can_issue) begin
            fu_issue_operand1 = rs_entries[issue_idx[1:0]].Vj_ready ? rs_entries[issue_idx[1:0]].Vj_data : cdb_value;
            fu_issue_operand2 = rs_entries[issue_idx[1:0]].Vk_ready ? rs_entries[issue_idx[1:0]].Vk_data : cdb_value;
        end else begin
            fu_issue_operand1 = 32'h0;
            fu_issue_operand2 = 32'h0;
        end
    end

    always_ff @(posedge clock or posedge reset) begin

        if (reset) begin
            rr_issue_ptr <= 2'd0;
            for (int i = 0; i < RS_DEPTH; i++) rs_entries[i].busy <= 1'b0;
        end else begin

            if (rs_dispatch_valid && !rs_full_out) begin
                rs_entries[rs_allocated_idx].busy        <= 1'b1;
                rs_entries[rs_allocated_idx].opcode      <= rs_dispatch_data.opcode;
                rs_entries[rs_allocated_idx].rob_idx     <= rs_dispatch_data.rob_idx;
                rs_entries[rs_allocated_idx].pc          <= rs_dispatch_data.pc;        
                rs_entries[rs_allocated_idx].imm         <= rs_dispatch_data.immediate; 
                rs_entries[rs_allocated_idx].pred_taken  <= rs_dispatch_data.predicted_taken;  
                rs_entries[rs_allocated_idx].pred_target <= rs_dispatch_data.predicted_target; 
                
                if (rs_dispatch_data.operand1_ready) begin
                    rs_entries[rs_allocated_idx].Vj_ready <= 1'b1;
                    rs_entries[rs_allocated_idx].Vj_data  <= rs_dispatch_data.operand1_val;
                end else if (cdb_valid && (rs_dispatch_data.operand1_rob_tag == cdb_rob_tag)) begin
                    rs_entries[rs_allocated_idx].Vj_ready <= 1'b1;
                    rs_entries[rs_allocated_idx].Vj_data  <= cdb_value;
                end else begin
                    rs_entries[rs_allocated_idx].Vj_ready   <= 1'b0;
                    rs_entries[rs_allocated_idx].Qj <= rs_dispatch_data.operand1_rob_tag;
                end

                if (rs_dispatch_data.operand2_ready) begin
                    rs_entries[rs_allocated_idx].Vk_ready <= 1'b1;
                    rs_entries[rs_allocated_idx].Vk_data  <= rs_dispatch_data.operand2_val;
                end else if (cdb_valid && (rs_dispatch_data.operand2_rob_tag == cdb_rob_tag)) begin
                    rs_entries[rs_allocated_idx].Vk_ready <= 1'b1;
                    rs_entries[rs_allocated_idx].Vk_data  <= cdb_value;
                end else begin
                    rs_entries[rs_allocated_idx].Vk_ready   <= 1'b0;
                    rs_entries[rs_allocated_idx].Qk <= rs_dispatch_data.operand2_rob_tag;
                end
            end
            
            if (cdb_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (rs_entries[i].busy) begin
                        if (!rs_entries[i].Vj_ready && (rs_entries[i].Qj == cdb_rob_tag)) begin
                            rs_entries[i].Vj_ready <= 1'b1;
                            rs_entries[i].Vj_data  <= cdb_value;
                        end
                        if (!rs_entries[i].Vk_ready && (rs_entries[i].Qk == cdb_rob_tag)) begin
                            rs_entries[i].Vk_ready <= 1'b1;
                            rs_entries[i].Vk_data  <= cdb_value;
                        end
                    end
                end
            end

            if (can_issue) begin
                rs_entries[issue_idx[1:0]].busy <= 1'b0;
                rr_issue_ptr <= issue_idx[1:0] + 2'd1;
            end
        end
    end
endmodule
