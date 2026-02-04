import config_pkg::*;
import cpu_types_pkg::*;

module branch_reservation_station (
    input  logic clock, reset,
    input  logic rs_dispatch_valid,
    input  branch_dispatch_packet_t rs_dispatch_data,
    output logic [4:0] rs_allocated_idx,
    output logic rs_full_out,
    
    output logic fu_issue_en,
    output logic [7:0]  fu_issue_opcode,
    output logic [31:0] fu_issue_operand1,
    output logic [31:0] fu_issue_operand2,
    output logic [31:0] fu_issue_pc,     
    output logic [7:0]  fu_issue_imm,    
    output logic [4:0]  fu_issue_rob_idx,
    
    input  logic cdb_valid,
    input  logic [4:0]  cdb_rob_tag,
    input  logic [31:0] cdb_value,
    input  logic fu_branch_busy
);

    parameter RS_DEPTH = 4;
    branch_rs_entry_t rs_entries[RS_DEPTH];
    logic [4:0] issue_idx;
    logic       can_issue;

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

        can_issue = 1'b0;
        issue_idx = 5'd0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_entries[i].busy && rs_entries[i].Vj_ready && rs_entries[i].Vk_ready && !fu_branch_busy) begin
                can_issue = 1'b1;
                issue_idx = i[4:0];
                break;
            end
        end
        
        fu_issue_en       = can_issue;
        fu_issue_opcode   = can_issue ? rs_entries[issue_idx[1:0]].opcode  : 8'h0;
        fu_issue_operand1 = can_issue ? rs_entries[issue_idx[1:0]].Vj_data : 32'h0;
        fu_issue_operand2 = can_issue ? rs_entries[issue_idx[1:0]].Vk_data : 32'h0;
        fu_issue_pc       = can_issue ? rs_entries[issue_idx[1:0]].pc      : 32'h0;
        fu_issue_imm      = can_issue ? rs_entries[issue_idx[1:0]].imm     : 8'h0;
        fu_issue_rob_idx  = can_issue ? rs_entries[issue_idx[1:0]].rob_idx : 5'h0;
    end

  
    always_ff @(posedge clock or posedge reset) begin
        logic [1:0] wr_ptr; 

        if (reset) begin
            for (int i = 0; i < RS_DEPTH; i++) rs_entries[i].busy <= 1'b0;
        end else begin
            wr_ptr = rs_allocated_idx[1:0]; 

            if (rs_dispatch_valid && !rs_full_out) begin
                rs_entries[wr_ptr].busy    <= 1'b1;
                rs_entries[wr_ptr].opcode  <= rs_dispatch_data.opcode;
                rs_entries[wr_ptr].rob_idx <= rs_dispatch_data.rob_idx;
                rs_entries[wr_ptr].pc      <= rs_dispatch_data.pc;        
                rs_entries[wr_ptr].imm     <= rs_dispatch_data.immediate; 
                
                if (rs_dispatch_data.operand1_ready) begin
                    rs_entries[wr_ptr].Vj_ready <= 1'b1;
                    rs_entries[wr_ptr].Vj_data  <= rs_dispatch_data.operand1_val;
                end else if (cdb_valid && (rs_dispatch_data.operand1_rob_tag == cdb_rob_tag)) begin
                    rs_entries[wr_ptr].Vj_ready <= 1'b1;
                    rs_entries[wr_ptr].Vj_data  <= cdb_value;
                end else begin
                    rs_entries[wr_ptr].Vj_ready   <= 1'b0;
                    rs_entries[wr_ptr].Vj_rob_tag <= rs_dispatch_data.operand1_rob_tag;
                end

                if (rs_dispatch_data.operand2_ready) begin
                    rs_entries[wr_ptr].Vk_ready <= 1'b1;
                    rs_entries[wr_ptr].Vk_data  <= rs_dispatch_data.operand2_val;
                end else if (cdb_valid && (rs_dispatch_data.operand2_rob_tag == cdb_rob_tag)) begin
                    rs_entries[wr_ptr].Vk_ready <= 1'b1;
                    rs_entries[wr_ptr].Vk_data  <= cdb_value;
                end else begin
                    rs_entries[wr_ptr].Vk_ready   <= 1'b0;
                    rs_entries[wr_ptr].Vk_rob_tag <= rs_dispatch_data.operand2_rob_tag;
                end
            end
            
            if (cdb_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (rs_entries[i].busy) begin
                        if (!rs_entries[i].Vj_ready && (rs_entries[i].Vj_rob_tag == cdb_rob_tag)) begin
                            rs_entries[i].Vj_ready <= 1'b1;
                            rs_entries[i].Vj_data  <= cdb_value;
                        end
                        if (!rs_entries[i].Vk_ready && (rs_entries[i].Vk_rob_tag == cdb_rob_tag)) begin
                            rs_entries[i].Vk_ready <= 1'b1;
                            rs_entries[i].Vk_data  <= cdb_value;
                        end
                    end
                end
            end

            if (fu_issue_en) rs_entries[issue_idx[1:0]].busy <= 1'b0;
        end
    end
endmodule

module branch_unit (
    input  logic        clock, reset,
    input  logic        fu_issue_en,
    input  logic [7:0]  fu_issue_opcode,
    input  logic [31:0] fu_issue_operand1,
    input  logic [31:0] fu_issue_operand2,
    input  logic [31:0] fu_issue_pc,  
    input  logic [7:0]  fu_issue_imm, 
    input  logic [4:0]  fu_issue_rob_idx,
    output logic        branch_cdb_valid,
    output logic [4:0]  branch_cdb_tag,
    output logic [31:0] branch_cdb_val,
    output logic        busy
);
    logic [9:0] target_pc;
    logic taken;

    always_comb begin
        case (fu_issue_opcode)module branch_reservation_station (
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

            8'hC4:   taken = (fu_issue_operand1 == fu_issue_operand2); // JE
            default: taken = 1'b0;
        endcase
        target_pc = taken ? (fu_issue_pc[9:0] + {{2{fu_issue_imm[7]}}, fu_issue_imm}) : (fu_issue_pc[9:0] + 10'd1);
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            branch_cdb_valid <= 1'b0;
            branch_cdb_tag   <= '0;
            branch_cdb_val   <= '0;
            busy <= 1'b0;
        end else if (fu_issue_en) begin
            branch_cdb_valid <= 1'b1;
            branch_cdb_tag   <= fu_issue_rob_idx;
            branch_cdb_val   <= {12'b0, target_pc, 9'b0, taken}; 
        end else begin
            branch_cdb_valid <= 1'b0;
        end
    end
endmodule
