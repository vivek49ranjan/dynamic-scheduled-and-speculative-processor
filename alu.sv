import config_pkg::*;
import cpu_types_pkg::*;

module reservation_station (
    input  logic clk, reset,
    
    // Dispatch Interface
    input  logic rs_dispatch_valid,
    input  alu_dispatch_packet_t rs_dispatch_data,
    output logic [4:0] rs_allocated_idx,
    output logic rs_full_out,
    
    // Issue Interface
    output logic [7:0]  fu_issue_opcode,
    output logic [31:0] fu_issue_operand1,
    output logic [31:0] fu_issue_operand2,
    output logic [4:0]  fu_issue_dest_reg,
    output logic [4:0]  fu_issue_rob_idx,
    output logic        fu_issue_en,
    
    // CDB Sniffing
    input  logic        cdb_valid,
    input  logic [4:0]  cdb_rob_tag,
    input  logic [31:0] cdb_value,
    
    // Status Interface
    output rs_status_t  rs_status_out[7:0],
    input  logic [7:0]  rs_issue_en_in,
    
    input  logic fu_add_sub_busy, fu_logical_busy, fu_shift_busy, 
    input  logic fu_rotate_busy, fu_inc_dec_busy, fu_abs_busy, fu_compare_busy
);

    parameter RS_DEPTH = 8;
    alu_rs_entry_t rs_entries[RS_DEPTH];
    
    logic [2:0] current_issued_idx;
    logic       is_issuing;

    // --- Combinational Logic ---
    always_comb begin
        // Allocation
        rs_full_out = 1'b1;
        rs_allocated_idx = 5'd0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (!rs_entries[i].busy) begin
                rs_allocated_idx = i[4:0];
                rs_full_out = 1'b0;
                break;
            end
        end

        // Issue Selection
        fu_issue_en = 1'b0;
        is_issuing  = 1'b0;
        current_issued_idx = 3'd0;
        {fu_issue_opcode, fu_issue_operand1, fu_issue_operand2, fu_issue_dest_reg, fu_issue_rob_idx} = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_issue_en_in[i]) begin
                fu_issue_en       = 1'b1;
                is_issuing        = 1'b1;
                current_issued_idx = i[2:0];
                fu_issue_opcode   = rs_entries[i].opcode;
                fu_issue_operand1 = rs_entries[i].V_j;
                fu_issue_operand2 = rs_entries[i].V_k;
                fu_issue_dest_reg = rs_entries[i].dest_reg;
                fu_issue_rob_idx  = rs_entries[i].rob_idx;
                break;
            end
        end
        
        // Status Reporting
        for (int i = 0; i < RS_DEPTH; i++) begin
            rs_status_out[i].valid   = rs_entries[i].busy;
            rs_status_out[i].ready   = rs_entries[i].Vj_valid && rs_entries[i].Vk_valid;
            rs_status_out[i].rob_idx = rs_entries[i].rob_idx;
            
            case (rs_entries[i].opcode[7:5])
                3'b000:  rs_status_out[i].fu_ready = !fu_add_sub_busy;
                3'b011:  rs_status_out[i].fu_ready = !fu_logical_busy;
                3'b100:  rs_status_out[i].fu_ready = !fu_shift_busy;
                3'b101:  rs_status_out[i].fu_ready = !fu_rotate_busy;
                3'b110:  rs_status_out[i].fu_ready = !fu_inc_dec_busy;
                3'b111:  rs_status_out[i].fu_ready = !fu_abs_busy && !fu_compare_busy;
                default: rs_status_out[i].fu_ready = 1'b1;
            endcase
        end
    end

    // --- Sequential Logic ---
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                rs_entries[i].busy <= 1'b0;
            end
        end else begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                // 1. Clear on Issue
                if (is_issuing && (current_issued_idx == i[2:0])) begin
                    rs_entries[i].busy <= 1'b0;
                end

                // 2. Dispatch (Priority over Clear)
                if (rs_dispatch_valid && !rs_full_out && (rs_allocated_idx[2:0] == i[2:0])) begin
                    rs_entries[i].busy     <= 1'b1;
                    rs_entries[i].opcode   <= rs_dispatch_data.opcode;
                    rs_entries[i].rob_idx  <= rs_dispatch_data.rob_idx;
                    rs_entries[i].dest_reg <= rs_dispatch_data.dest_reg;
                    
                    // Sniffing op1
                    if (cdb_valid && (rs_dispatch_data.op1_rob_tag == cdb_rob_tag)) begin
                        rs_entries[i].Vj_valid <= 1'b1;
                        rs_entries[i].V_j      <= cdb_value;
                    end else begin
                        rs_entries[i].Vj_valid <= rs_dispatch_data.op1_is_ready;
                        rs_entries[i].V_j      <= rs_dispatch_data.op1_val;
                        rs_entries[i].Qj       <= rs_dispatch_data.op1_rob_tag;
                    end

                    // Sniffing op2
                    if (cdb_valid && (rs_dispatch_data.op2_rob_tag == cdb_rob_tag)) begin
                        rs_entries[i].Vk_valid <= 1'b1;
                        rs_entries[i].V_k      <= cdb_value;
                    end else begin
                        rs_entries[i].Vk_valid <= rs_dispatch_data.op2_is_ready;
                        rs_entries[i].V_k      <= rs_dispatch_data.op2_val;
                        rs_entries[i].Qk       <= rs_dispatch_data.op2_rob_tag;
                    end
                end 
                // 3. Normal CDB Sniffing
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
            end // end for loop
        end // end else
    end // end always_ff
endmodule
// --- ALU TOP AND FUNCTIONAL UNITS ---
// (Paste existing alu_top and FU modules here, they are structurally correct)
`timescale 1ns / 1ps
import config_pkg::*;
import cpu_types_pkg::*;

module alu_top (
    input  logic        clk, reset,
    
    input  logic [7:0]  fu_issue_opcode,
    input  logic [31:0] fu_issue_operand1,
    input  logic [31:0] fu_issue_operand2,
    input  logic [4:0]  fu_issue_dest_reg, 
    input  logic [4:0]  fu_issue_rob_idx,
    input  logic        fu_issue_en,

    output logic [31:0] cdb_result_value,
    output logic [4:0]  cdb_result_rob_tag,
    output logic [4:0]  cdb_dest_reg,       
    output logic        cdb_result_valid,

    output logic fu_add_sub_busy, fu_logical_busy, fu_shift_busy, 
    output logic fu_rotate_busy, fu_inc_dec_busy, fu_abs_busy, fu_compare_busy
);

    logic [31:0] res_add, res_log, res_shf, res_rot, res_inc, res_abs, res_cmp;
    logic [4:0]  tag_add, tag_log, tag_shf, tag_rot, tag_inc, tag_abs, tag_cmp;
    logic [4:0]  dst_add, dst_log, dst_shf, dst_rot, dst_inc, dst_abs, dst_cmp;
    logic        v_add, v_log, v_shf, v_rot, v_inc, v_abs, v_cmp;

    
    add_sub_fu u_add_sub_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b000)),
        .a(fu_issue_operand1), .b(fu_issue_operand2), .op(fu_issue_opcode[0]),
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_add_sub_busy),
        .result(res_add), .rob_idx_out(tag_add), .dest_reg_out(dst_add), .done(v_add)
    );

    logica_fu u_logical_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b011)),
        .a(fu_issue_operand1), .b(fu_issue_operand2), .op(fu_issue_opcode[1:0]),
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_logical_busy),
        .result(res_log), .rob_idx_out(tag_log), .dest_reg_out(dst_log), .done(v_log)
    );

    shift_fu u_shift_fu (
        .clk(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b100)),
        .a(fu_issue_operand1), .op(fu_issue_opcode[0]),
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_shift_busy),
        .result(res_shf), .rob_idx_out(tag_shf), .dest_reg_out(dst_shf), .done(v_shf)
    );

    rotate_fu u_rotate_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b101)),
        .a(fu_issue_operand1), .op(fu_issue_opcode[0]),
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_rotate_busy),
        .result(res_rot), .rob_idx_out(tag_rot), .dest_reg_out(dst_rot), .done(v_rot)
    );

    increment_decrement_fu u_inc_dec_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b110)),
        .a(fu_issue_operand1), .op(fu_issue_opcode[0]),
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_inc_dec_busy),
        .result(res_inc), .rob_idx_out(tag_inc), .dest_reg_out(dst_inc), .done(v_inc)
    );

    abs_fu u_abs_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode == OPCODE_ABS)),
        .a(fu_issue_operand1), 
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_abs_busy),
        .result(res_abs), .rob_idx_out(tag_abs), .dest_reg_out(dst_abs), .done(v_abs)
    );

    compare_fu u_compare_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode == OPCODE_COMPARE)),
        .a(fu_issue_operand1), .b(fu_issue_operand2), 
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_compare_busy),
        .result(res_cmp), .rob_idx_out(tag_cmp), .dest_reg_out(dst_cmp), .done(v_cmp)
    );

    // --- CDB Arbiter (Fixed Priority Multiplexer) ---
    // Transfers result, rob_tag, and dest_reg together
    always_comb begin
        cdb_result_valid   = 1'b0;
        cdb_result_value   = 32'b0;
        cdb_result_rob_tag = 5'd0;
        cdb_dest_reg       = 5'd0;

        if (v_add) begin
            cdb_result_valid   = 1'b1;
            cdb_result_value   = res_add;
            cdb_result_rob_tag = tag_add;
            cdb_dest_reg       = dst_add;
        end else if (v_log) begin
            cdb_result_valid   = 1'b1;
            cdb_result_value   = res_log;
            cdb_result_rob_tag = tag_log;
            cdb_dest_reg       = dst_log;
        end else if (v_shf) begin
            cdb_result_valid   = 1'b1;
            cdb_result_value   = res_shf;
            cdb_result_rob_tag = tag_shf;
            cdb_dest_reg       = dst_shf;
        end else if (v_rot) begin
            cdb_result_valid   = 1'b1;
            cdb_result_value   = res_rot;
            cdb_result_rob_tag = tag_rot;
            cdb_dest_reg       = dst_rot;
        end else if (v_inc) begin
            cdb_result_valid   = 1'b1;
            cdb_result_value   = res_inc;
            cdb_result_rob_tag = tag_inc;
            cdb_dest_reg       = dst_inc;
        end else if (v_abs) begin
            cdb_result_valid   = 1'b1;
            cdb_result_value   = res_abs;
            cdb_result_rob_tag = tag_abs;
            cdb_dest_reg       = dst_abs;
        end else if (v_cmp) begin
            cdb_result_valid   = 1'b1;
            cdb_result_value   = res_cmp;
            cdb_result_rob_tag = tag_cmp;
            cdb_dest_reg       = dst_cmp;
        end
    end
endmodule

// --- 1. ADD/SUB UNIT ---
module add_sub_fu (
    input  logic [31:0] a, b, 
    input  logic clock, reset, en, op, 
    input  logic [4:0]  rob_idx_in, 
    input  logic [4:0]  dest_reg_in,
    output logic [31:0] result, 
    output logic        done, 
    output logic [4:0]  rob_idx_out, 
    output logic [4:0]  dest_reg_out, 
    output logic        busy
);
    logic [31:0] a_reg, b_reg;
    logic        op_reg;
    logic [4:0]  rob_idx_reg, dest_reg_reg;
    logic        state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin
                a_reg <= a; b_reg <= b; op_reg <= op;
                rob_idx_reg <= rob_idx_in; dest_reg_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                result <= op_reg ? (a_reg - b_reg) : (a_reg + b_reg);
                rob_idx_out <= rob_idx_reg; dest_reg_out <= dest_reg_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

// --- 2. LOGICAL UNIT ---
module logica_fu (
    input  logic [31:0] a, b, 
    input  logic [1:0]  op, 
    input  logic reset, clock, en, 
    input  logic [4:0]  rob_idx_in, 
    input  logic [4:0]  dest_reg_in,
    output logic [31:0] result, 
    output logic        done, 
    output logic [4:0]  rob_idx_out, 
    output logic [4:0]  dest_reg_out, 
    output logic        busy
);
    logic [31:0] a_reg, b_reg;
    logic [1:0]  op_reg;
    logic [4:0]  rob_idx_reg, dest_reg_reg;
    logic        state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin
                a_reg <= a; b_reg <= b; op_reg <= op;
                rob_idx_reg <= rob_idx_in; dest_reg_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                case(op_reg)
                    2'b00: result <= a_reg & b_reg;
                    2'b01: result <= a_reg | b_reg;
                    2'b10: result <= a_reg ^ b_reg;
                    2'b11: result <= ~a_reg;
                endcase
                rob_idx_out <= rob_idx_reg; dest_reg_out <= dest_reg_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

// --- 3. SHIFT UNIT ---
module shift_fu (
    input  logic [31:0] a, 
    input  logic reset, clk, en, op, 
    input  logic [4:0]  rob_idx_in, 
    input  logic [4:0]  dest_reg_in,
    output logic [31:0] result, 
    output logic        done, 
    output logic [4:0]  rob_idx_out, 
    output logic [4:0]  dest_reg_out, 
    output logic        busy
);
    logic [31:0] a_reg;
    logic        op_reg;
    logic [4:0]  rob_idx_reg, dest_reg_reg;
    logic        state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin
                a_reg <= a; op_reg <= op;
                rob_idx_reg <= rob_idx_in; dest_reg_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                result <= op_reg ? (a_reg >> 1) : (a_reg << 1);
                rob_idx_out <= rob_idx_reg; dest_reg_out <= dest_reg_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

// --- 4. ROTATE UNIT ---
module rotate_fu (
    input  logic [31:0] a, 
    input  logic reset, clock, en, op, 
    input  logic [4:0]  rob_idx_in, 
    input  logic [4:0]  dest_reg_in,
    output logic [31:0] result, 
    output logic        done, 
    output logic [4:0]  rob_idx_out, 
    output logic [4:0]  dest_reg_out, 
    output logic        busy
);
    logic [31:0] a_reg;
    logic        op_reg;
    logic [4:0]  rob_idx_reg, dest_reg_reg;
    logic        state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin
                a_reg <= a; op_reg <= op;
                rob_idx_reg <= rob_idx_in; dest_reg_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                result <= op_reg ? {a_reg[0], a_reg[31:1]} : {a_reg[30:0], a_reg[31]};
                rob_idx_out <= rob_idx_reg; dest_reg_out <= dest_reg_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

// --- 5. INCREMENT/DECREMENT UNIT ---
module increment_decrement_fu (
    input  logic [31:0] a, 
    input  logic op, clock, reset, en, 
    input  logic [4:0]  rob_idx_in, 
    input  logic [4:0]  dest_reg_in,
    output logic [31:0] result, 
    output logic        done, 
    output logic [4:0]  rob_idx_out, 
    output logic [4:0]  dest_reg_out, 
    output logic        busy
);
    logic [31:0] a_reg;
    logic        op_reg;
    logic [4:0]  rob_idx_reg, dest_reg_reg;
    logic        state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin
                a_reg <= a; op_reg <= op;
                rob_idx_reg <= rob_idx_in; dest_reg_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                result <= op_reg ? (a_reg - 1) : (a_reg + 1);
                rob_idx_out <= rob_idx_reg; dest_reg_out <= dest_reg_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

// --- 6. ABSOLUTE VALUE UNIT ---
module abs_fu (
    input  logic clock, reset, en, 
    input  logic [31:0] a, 
    input  logic [4:0]  rob_idx_in, 
    input  logic [4:0]  dest_reg_in,
    output logic [31:0] result, 
    output logic        done, 
    output logic [4:0]  rob_idx_out, 
    output logic [4:0]  dest_reg_out, 
    output logic        busy
);
    logic [31:0] a_reg;
    logic [4:0]  rob_idx_reg, dest_reg_reg;
    logic        state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin
                a_reg <= a;
                rob_idx_reg <= rob_idx_in; dest_reg_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                result <= a_reg[31] ? (~a_reg + 1) : a_reg;
                rob_idx_out <= rob_idx_reg; dest_reg_out <= dest_reg_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

// --- 7. COMPARE UNIT ---
module compare_fu (
    input  logic [31:0] a, b, 
    input  logic clock, reset, en, 
    input  logic [4:0]  rob_idx_in, 
    input  logic [4:0]  dest_reg_in,
    output logic [31:0] result, 
    output logic        done, 
    output logic [4:0]  rob_idx_out, 
    output logic [4:0]  dest_reg_out, 
    output logic        busy
);
    logic [31:0] a_reg, b_reg;
    logic [4:0]  rob_idx_reg, dest_reg_reg;
    logic        state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin
                a_reg <= a; b_reg <= b;
                rob_idx_reg <= rob_idx_in; dest_reg_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                if ($signed(a_reg) > $signed(b_reg))      result <= 32'd1;
                else if ($signed(a_reg) < $signed(b_reg)) result <= -32'd1;
                else                                      result <= 32'd0;
                rob_idx_out <= rob_idx_reg; dest_reg_out <= dest_reg_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule
