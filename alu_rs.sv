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
    
    output rs_status_t  rs_status_out[7:0],
    input  logic [7:0]  rs_issue_en_in,
    
    input  logic fu_add_sub_busy, fu_logical_busy, fu_shift_busy, fu_compare_busy
);

    parameter RS_DEPTH = 8;
    alu_rs_entry_t rs_entries[RS_DEPTH];
    
    logic [2:0] current_issued_idx;
    logic       is_issuing;

    logic [2:0] rr_issue_ptr;

    logic [RS_DEPTH-1:0] entry_ready;
    logic [31:0]         entry_val_1 [RS_DEPTH-1:0];
    logic [31:0]         entry_val_2 [RS_DEPTH-1:0];
	 logic [4:0]          rs_allocated_idx;
    always_comb begin
        rs_full_out = 1'b1;
        rs_allocated_idx = 5'd0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (!rs_entries[i].busy) begin
                rs_allocated_idx = i[4:0];
                rs_full_out = 1'b0;
                break;
            end
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            logic op1_rdy;
            logic op2_rdy;

            if (rs_entries[i].Vj_valid) begin
                op1_rdy = 1'b1;
                entry_val_1[i] = rs_entries[i].V_j;
            end
            else if (cdb_valid && (rs_entries[i].Qj == cdb_rob_tag)) begin
                op1_rdy = 1'b1;
                entry_val_1[i] = cdb_value;
            end
            else begin
                op1_rdy = 1'b0;
                entry_val_1[i] = 32'd0;
            end

            if (rs_entries[i].Vk_valid) begin
                op2_rdy = 1'b1;
                entry_val_2[i] = rs_entries[i].V_k;
            end
            else if (cdb_valid && (rs_entries[i].Qk == cdb_rob_tag)) begin
                op2_rdy = 1'b1;
                entry_val_2[i] = cdb_value;
            end
            else begin
                op2_rdy = 1'b0;
                entry_val_2[i] = 32'd0;
            end

            entry_ready[i] = op1_rdy && op2_rdy;
            
            rs_status_out[i].valid   = rs_entries[i].busy;
            rs_status_out[i].ready   = entry_ready[i];
            rs_status_out[i].rob_idx = rs_entries[i].rob_idx;
            rs_status_out[i].fu_type = rs_entries[i].opcode[7:5];
            
            case (rs_entries[i].opcode[7:5])
                3'b000:  rs_status_out[i].fu_ready = !fu_add_sub_busy;
                3'b011:  rs_status_out[i].fu_ready = !fu_logical_busy;
                3'b100:  rs_status_out[i].fu_ready = !fu_shift_busy;
                3'b111:  rs_status_out[i].fu_ready = !fu_compare_busy;
                default: rs_status_out[i].fu_ready = 1'b1;
            endcase
        end

        fu_issue_en = 1'b0;
        is_issuing  = 1'b0;
        current_issued_idx = 3'd0;
        fu_issue_opcode    = '0;
        fu_issue_operand1  = '0;
        fu_issue_operand2  = '0;
        fu_issue_dest_reg  = '0;
        fu_issue_rob_idx   = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            logic [2:0] check_idx;
            check_idx = rr_issue_ptr + i[2:0];

            if (rs_issue_en_in[check_idx]) begin
                fu_issue_en       = 1'b1;
                is_issuing        = 1'b1;
                current_issued_idx = check_idx;
                fu_issue_opcode   = rs_entries[check_idx].opcode;
                fu_issue_operand1 = entry_val_1[check_idx];
                fu_issue_operand2 = entry_val_2[check_idx];
                fu_issue_dest_reg = rs_entries[check_idx].dest_reg;
                fu_issue_rob_idx  = rs_entries[check_idx].rob_idx;
                break;
            end
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
            if (is_issuing) begin
                rr_issue_ptr <= current_issued_idx + 3'd1;
            end

            for (int i = 0; i < RS_DEPTH; i++) begin
                if (is_issuing && (current_issued_idx == i[2:0])) begin
                    rs_entries[i].busy <= 1'b0;
                end

                if (rs_dispatch_valid && !rs_full_out && (rs_allocated_idx[2:0] == i[2:0])) begin
                    rs_entries[i].busy     <= 1'b1;
                    rs_entries[i].opcode   <= rs_dispatch_data.opcode;
                    rs_entries[i].rob_idx  <= rs_dispatch_data.rob_idx;
                    rs_entries[i].dest_reg <= rs_dispatch_data.dest_reg;
                    
                    if (cdb_valid && (rs_dispatch_data.op1_rob_tag == cdb_rob_tag)) begin
                        rs_entries[i].Vj_valid <= 1'b1;
                        rs_entries[i].V_j      <= cdb_value;
                    end
                    else begin
                        rs_entries[i].Vj_valid <= rs_dispatch_data.op1_is_ready;
                        rs_entries[i].V_j      <= rs_dispatch_data.op1_val;
                        rs_entries[i].Qj       <= rs_dispatch_data.op1_rob_tag;
                    end

                    if (cdb_valid && (rs_dispatch_data.op2_rob_tag == cdb_rob_tag)) begin
                        rs_entries[i].Vk_valid <= 1'b1;
                        rs_entries[i].V_k      <= cdb_value;
                    end
                    else begin
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
