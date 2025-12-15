module branch_reservation_station (
    input wire clk,
    input wire reset,

    input wire rs_dispatch_valid,
    input branch_dispatch_packet_t rs_dispatch_data,
    output logic [3:0] rs_allocated_idx,
    output logic rs_full_out,

    output logic fu_issue_en,
    output logic [7:0] fu_issue_opcode,
    output logic [31:0] fu_issue_operand1,
    output logic [31:0] fu_issue_operand2,
    output logic [3:0] fu_issue_rob_idx,

    input wire cdb_valid,
    input wire [3:0] cdb_rob_tag,
    input wire [31:0] cdb_value,

    input wire fu_branch_busy
);
    import config_pkg::*;
    import cpu_types_pkg::*;

    parameter RS_DEPTH = 4;
    
    typedef struct packed {
        logic busy;
        logic V_j;
        logic V_k;
        logic [31:0] Qj;
        logic [31:0] Qk;
        logic [7:0] opcode;
        logic [3:0] rob_idx;
    } branch_rs_entry_t;

    branch_rs_entry_t rs_entries[RS_DEPTH];
    logic [RS_DEPTH-1:0] rs_ready_to_issue;

    logic [3:0] calculated_next_free_rs_idx;
    logic calculated_rs_full_out;
    logic selected_fu_en_comb;
    logic [7:0] selected_opcode_comb;
    logic [31:0] selected_operand1_comb;
    logic [31:0] selected_operand2_comb;
    logic [3:0] selected_rob_idx_comb;
    logic [3:0] selected_rs_entry_idx_comb;
    reg [3:0] issue_arbiter_ptr;
    logic [3:0] current_rs_idx;
    
    // Sniffing logic
    logic op1_ready, op2_ready;
    logic [31:0] op1_val, op2_val;

    always_comb begin
        // Sniffing
        if (!rs_dispatch_data.operand1_ready && cdb_valid && (rs_dispatch_data.operand1_rob_tag == cdb_rob_tag)) begin
            op1_ready = 1'b1; op1_val = cdb_value;
        end else begin
            op1_ready = rs_dispatch_data.operand1_ready; op1_val = rs_dispatch_data.operand1_val;
        end
        
        if (!rs_dispatch_data.operand2_ready && cdb_valid && (rs_dispatch_data.operand2_rob_tag == cdb_rob_tag)) begin
            op2_ready = 1'b1; op2_val = cdb_value;
        end else begin
            op2_ready = rs_dispatch_data.operand2_ready; op2_val = rs_dispatch_data.operand2_val;
        end

        rs_ready_to_issue = '0;
        selected_fu_en_comb = 1'b0;
        selected_opcode_comb = '0;
        selected_operand1_comb = '0;
        selected_operand2_comb = '0;
        selected_rob_idx_comb = '0;
        selected_rs_entry_idx_comb = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            current_rs_idx = (issue_arbiter_ptr + i) % RS_DEPTH;
            if (rs_entries[current_rs_idx].busy && rs_entries[current_rs_idx].V_j && rs_entries[current_rs_idx].V_k) begin
                if (!fu_branch_busy) begin 
                    rs_ready_to_issue[current_rs_idx] = 1'b1; 
                end
            end
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            current_rs_idx = (issue_arbiter_ptr + i) % RS_DEPTH;
            if (rs_ready_to_issue[current_rs_idx]) begin
                selected_fu_en_comb = 1'b1;
                selected_opcode_comb = rs_entries[current_rs_idx].opcode;
                selected_operand1_comb = rs_entries[current_rs_idx].Qj;
                selected_operand2_comb = rs_entries[current_rs_idx].Qk;
                selected_rob_idx_comb = rs_entries[current_rs_idx].rob_idx;
                selected_rs_entry_idx_comb = current_rs_idx[3:0];
                break;
            end
        end

        fu_issue_en = selected_fu_en_comb; 
        fu_issue_opcode = selected_opcode_comb;
        fu_issue_operand1 = selected_operand1_comb; 
        fu_issue_operand2 = selected_operand2_comb;
        fu_issue_rob_idx = selected_rob_idx_comb;

        calculated_next_free_rs_idx = '0; 
        calculated_rs_full_out = 1'b1;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (!rs_entries[i].busy) begin
                if (calculated_rs_full_out) begin 
                    calculated_next_free_rs_idx = i[3:0]; 
                    calculated_rs_full_out = 1'b0; 
                end
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                rs_entries[i].busy <= 1'b0; 
                rs_entries[i].V_j <= 1'b0; 
                rs_entries[i].V_k <= 1'b0;
                rs_entries[i].Qj <= '0; 
                rs_entries[i].Qk <= '0; 
                rs_entries[i].opcode <= '0; 
                rs_entries[i].rob_idx <= '0;
            end
            rs_allocated_idx <= '0; 
            rs_full_out <= 1'b0; 
            issue_arbiter_ptr <= '0;
        end else begin
            rs_full_out <= calculated_rs_full_out; 
            rs_allocated_idx <= calculated_next_free_rs_idx;

            if (rs_dispatch_valid && !calculated_rs_full_out) begin
                rs_entries[calculated_next_free_rs_idx].busy <= 1'b1;
                rs_entries[calculated_next_free_rs_idx].opcode <= rs_dispatch_data.opcode;
                rs_entries[calculated_next_free_rs_idx].rob_idx <= rs_dispatch_data.rob_idx;

                if (op1_ready) begin 
                    rs_entries[calculated_next_free_rs_idx].V_j <= 1'b1;
                    rs_entries[calculated_next_free_rs_idx].Qj <= op1_val;
                end else begin 
                    rs_entries[calculated_next_free_rs_idx].V_j <= 1'b0;
                    rs_entries[calculated_next_free_rs_idx].Qj <= {28'b0, rs_dispatch_data.operand1_rob_tag};
                end

                if (op2_ready) begin 
                    rs_entries[calculated_next_free_rs_idx].V_k <= 1'b1;
                    rs_entries[calculated_next_free_rs_idx].Qk <= op2_val;
                end else begin 
                    rs_entries[calculated_next_free_rs_idx].V_k <= 1'b0;
                    rs_entries[calculated_next_free_rs_idx].Qk <= {28'b0, rs_dispatch_data.operand2_rob_tag};
                end
            end

            if (cdb_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (rs_entries[i].busy) begin
                        if (!rs_entries[i].V_j && (rs_entries[i].Qj[3:0] == cdb_rob_tag)) begin 
                            rs_entries[i].V_j <= 1'b1;
                            rs_entries[i].Qj <= cdb_value;
                        end
                        if (!rs_entries[i].V_k && (rs_entries[i].Qk[3:0] == cdb_rob_tag)) begin
                            rs_entries[i].V_k <= 1'b1; 
                            rs_entries[i].Qk <= cdb_value;
                        end
                    end
                end
            end

            if (fu_issue_en) begin
                rs_entries[selected_rs_entry_idx_comb].busy <= 1'b0;
                issue_arbiter_ptr <= (selected_rs_entry_idx_comb + 1) % RS_DEPTH;
            end
        end
    end
endmodule
module branch_unit (
    input clock,
    input reset,
    
    input logic fu_issue_en,
    input logic [7:0] fu_issue_opcode,
    input logic [31:0] fu_issue_operand1,
    input logic [31:0] fu_issue_operand2,
    input logic [3:0] fu_issue_rob_idx,
    
    output logic branch_taken,
    output logic [7:0] branch_address, // Misnomer: Usually implies branch evaluation result
    output logic busy,
    output logic stop_stall
);
    import config_pkg::*;

    reg [7:0] internal_branch_address;
    reg internal_branch_taken;
    reg branch_evaluating;

    reg [31:0] op1_val_reg, op2_val_reg;
    reg [7:0] opcode_reg;
    reg [3:0] rob_idx_reg;

    assign busy = branch_evaluating;
    assign branch_taken = internal_branch_taken;
    assign branch_address = internal_branch_address;
    assign stop_stall = !branch_evaluating;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            internal_branch_taken <= 1'b0; 
            internal_branch_address <= 8'b0; 
            branch_evaluating <= 1'b0;
        end else begin
            if (branch_evaluating) begin
                // Evaluation Cycle
                internal_branch_taken <= 1'b0;
                case (opcode_reg)
                    JLT: internal_branch_taken <= ($signed(op1_val_reg) < $signed(op2_val_reg));
                    JGT: internal_branch_taken <= ($signed(op1_val_reg) > $signed(op2_val_reg));
                    JNE: internal_branch_taken <= (op1_val_reg != op2_val_reg);
                    JLE: internal_branch_taken <= ($signed(op1_val_reg) <= $signed(op2_val_reg));
                    JE:  internal_branch_taken <= (op1_val_reg == op2_val_reg);
                    default: internal_branch_taken <= 1'b0;
                endcase
                internal_branch_address <= internal_branch_taken ? 8'hAA : 8'h00; // Debug value
                branch_evaluating <= 1'b0;
            end else if (fu_issue_en) begin
                // Latch Inputs
                op1_val_reg <= fu_issue_operand1;
                op2_val_reg <= fu_issue_operand2;
                opcode_reg <= fu_issue_opcode;
                rob_idx_reg <= fu_issue_rob_idx;
                branch_evaluating <= 1'b1;
            end
        end
    end
endmodule

