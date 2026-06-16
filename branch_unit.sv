module branch_unit (
    input  logic        clock, reset,
    input  logic        fu_issue_en,
    input  logic [7:0]  fu_issue_opcode,
    input  logic [31:0] fu_issue_operand1,
    input  logic [31:0] fu_issue_operand2,
    input  logic [31:0] fu_issue_pc,  
    input  logic [31:0] fu_issue_imm, 
    input  logic [4:0]  fu_issue_rob_idx,
    input  logic        fu_issue_pred_taken,  
    input  logic [9:0]  fu_issue_pred_target,  
    output logic        branch_cdb_valid,
    output logic [4:0]  branch_cdb_tag,
    output logic [31:0] branch_cdb_val,
    output logic        branch_cdb_mispredict,
    output logic [9:0]  branch_target_pc_out 
);
    logic [9:0] target_pc;
    logic taken;
    logic [9:0] word_offset;
    logic is_mispredict;

    always_comb begin
        case (fu_issue_opcode)
            8'b11000100, JE:   taken = (fu_issue_operand1 == fu_issue_operand2);
            8'b11000010, JNE:  taken = (fu_issue_operand1 != fu_issue_operand2);
            8'b11000000, JLT:  taken = ($signed(fu_issue_operand1) < $signed(fu_issue_operand2));
            8'b11000101, JGE:  taken = ($signed(fu_issue_operand1) >= $signed(fu_issue_operand2));
            8'b11000110, JLTU: taken = (fu_issue_operand1 < fu_issue_operand2);
            8'b11000111, JGEU: taken = (fu_issue_operand1 >= fu_issue_operand2);
            JAL, JALR:         taken = 1'b1;
            default:           taken = 1'b0;
        endcase
        
        word_offset = $signed(fu_issue_imm) >>> 2;
        
        if (fu_issue_opcode == JALR) begin
            target_pc = (fu_issue_operand1 + $signed(fu_issue_imm)) >> 2;
        end else begin
            target_pc = taken ? (fu_issue_pc[9:0] + word_offset) : (fu_issue_pc[9:0] + 10'd1);
        end
        
        is_mispredict = (taken != fu_issue_pred_taken) || 
                        (taken && (target_pc != fu_issue_pred_target));
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            branch_cdb_valid      <= 1'b0;
            branch_cdb_tag        <= '0;
            branch_cdb_val        <= '0;
            branch_cdb_mispredict <= 1'b0; 
            branch_target_pc_out  <= '0;
        end
        else begin
            if (fu_issue_en) begin
                branch_cdb_valid      <= 1'b1;
                branch_cdb_tag        <= fu_issue_rob_idx;
                branch_cdb_mispredict <= is_mispredict; 
                branch_target_pc_out  <= target_pc; 
                if (fu_issue_opcode == JAL || fu_issue_opcode == JALR) begin
                    branch_cdb_val <= {20'b0, (fu_issue_pc[9:0] + 10'd1), 2'b00}; 
                end else begin
                    branch_cdb_val <= 32'd0; 
                end
            end
            else begin
                branch_cdb_valid      <= 1'b0;
            end
        end
    end
endmodule
