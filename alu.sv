module reservation_station (
    input wire clk,
    input wire reset,

    input wire             rs_dispatch_valid,
    input alu_dispatch_packet_t rs_dispatch_data,
    output logic [3:0]     rs_allocated_idx,
    output logic           rs_full_out,

    output logic [7:0]     fu_issue_opcode,
    output logic [31:0]    fu_issue_operand1,
    output logic [31:0]    fu_issue_operand2,
    output logic [4:0]     fu_issue_dest_reg,
    output logic [3:0]     fu_issue_rob_idx,
    output logic           fu_issue_en,

    input wire             cdb_valid,
    input wire [3:0]       cdb_rob_tag,
    input wire [31:0]      cdb_value,

    output rs_status_t rs_status_out[7:0],
    input  logic [7:0]     rs_issue_en_in,

    input wire fu_add_sub_busy,
    input wire fu_logical_busy,
    input wire fu_shift_busy,
    input wire fu_rotate_busy,
    input wire fu_inc_dec_busy,
    input wire fu_abs_busy,
    input wire fu_compare_busy
);
    import config_pkg::*;
    import cpu_types_pkg::*;

    parameter RS_DEPTH = 8;
    alu_rs_entry_t rs_entries[RS_DEPTH];
    logic [3:0]    calculated_next_free_rs_idx;
    logic          calculated_rs_full_out;
    logic [3:0]    issued_rs_idx;

    logic op1_real_ready, op2_real_ready;
    logic [31:0] op1_real_val, op2_real_val;

    always_comb begin
        if (!rs_dispatch_data.op1_is_ready && cdb_valid && (rs_dispatch_data.op1_rob_tag == cdb_rob_tag)) begin
            op1_real_ready = 1'b1;
            op1_real_val   = cdb_value;
        end else begin
            op1_real_ready = rs_dispatch_data.op1_is_ready;
            op1_real_val   = rs_dispatch_data.op1_val;
        end

        if (!rs_dispatch_data.op2_is_ready && cdb_valid && (rs_dispatch_data.op2_rob_tag == cdb_rob_tag)) begin
            op2_real_ready = 1'b1;
            op2_real_val   = cdb_value;
        end else begin
            op2_real_ready = rs_dispatch_data.op2_is_ready;
            op2_real_val   = rs_dispatch_data.op2_val;
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            rs_status_out[i].valid   = rs_entries[i].busy;
            rs_status_out[i].ready   = rs_entries[i].V_j && rs_entries[i].V_k;
            rs_status_out[i].rob_idx = rs_entries[i].rob_idx;
            
            rs_status_out[i].fu_ready = 1'b0;
            if (rs_entries[i].busy) begin
                case (rs_entries[i].opcode[7:5])
                    FU_ADD_SUB: rs_status_out[i].fu_ready = !fu_add_sub_busy;
                    FU_LOGICAL: rs_status_out[i].fu_ready = !fu_logical_busy;
                    FU_SHIFT:   rs_status_out[i].fu_ready = !fu_shift_busy;
                    FU_ROTATE:  rs_status_out[i].fu_ready = !fu_rotate_busy;
                    FU_INC_DEC: rs_status_out[i].fu_ready = !fu_inc_dec_busy;
                    FU_SPECIAL: begin
                        case (rs_entries[i].opcode)
                            OPCODE_ABS:     rs_status_out[i].fu_ready = !fu_abs_busy;
                            OPCODE_COMPARE: rs_status_out[i].fu_ready = !fu_compare_busy;
                            default:        rs_status_out[i].fu_ready = 1'b0;
                        endcase
                    end
                    default: rs_status_out[i].fu_ready = 1'b0;
                endcase
            end
        end

        fu_issue_en       = 1'b0;
        fu_issue_opcode   = '0;
        fu_issue_operand1 = '0;
        fu_issue_operand2 = '0;
        fu_issue_dest_reg = '0;
        fu_issue_rob_idx  = '0;
        issued_rs_idx     = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_issue_en_in[i]) begin
                fu_issue_en       = 1'b1;
                fu_issue_opcode   = rs_entries[i].opcode;
                fu_issue_operand1 = rs_entries[i].V_j ? rs_entries[i].Qj : rs_entries[i].Qj;
                fu_issue_operand2 = rs_entries[i].V_k ? rs_entries[i].Qk : rs_entries[i].Qk;
                fu_issue_dest_reg = rs_entries[i].dest_reg;
                fu_issue_rob_idx  = rs_entries[i].rob_idx;
                issued_rs_idx     = i[3:0];
                break;
            end
        end

        calculated_next_free_rs_idx = '0;
        calculated_rs_full_out = 1'b1;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (!rs_entries[i].busy) begin
                calculated_next_free_rs_idx = i[3:0];
                calculated_rs_full_out = 1'b0;
                break;
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                rs_entries[i].busy <= 1'b0;
                rs_entries[i].V_j <= 0; rs_entries[i].V_k <= 0;
            end
            rs_full_out <= 1'b0;
        end else begin
            rs_full_out <= calculated_rs_full_out;
            rs_allocated_idx <= calculated_next_free_rs_idx;

            if (rs_dispatch_valid && !calculated_rs_full_out) begin
                rs_entries[calculated_next_free_rs_idx].busy       <= 1'b1;
                rs_entries[calculated_next_free_rs_idx].opcode     <= rs_dispatch_data.opcode;
                rs_entries[calculated_next_free_rs_idx].dest_reg   <= rs_dispatch_data.dest_reg;
                rs_entries[calculated_next_free_rs_idx].rob_idx    <= rs_dispatch_data.rob_idx;

                if (op1_real_ready) begin
                    rs_entries[calculated_next_free_rs_idx].V_j <= 1'b1;
                    rs_entries[calculated_next_free_rs_idx].Qj  <= op1_real_val;
                end else begin
                    rs_entries[calculated_next_free_rs_idx].V_j <= 1'b0;
                    rs_entries[calculated_next_free_rs_idx].Qj  <= {28'b0, rs_dispatch_data.op1_rob_tag};
                end

                if (op2_real_ready) begin
                    rs_entries[calculated_next_free_rs_idx].V_k <= 1'b1;
                    rs_entries[calculated_next_free_rs_idx].Qk  <= op2_real_val;
                end else begin
                    rs_entries[calculated_next_free_rs_idx].V_k <= 1'b0;
                    rs_entries[calculated_next_free_rs_idx].Qk  <= {28'b0, rs_dispatch_data.op2_rob_tag};
                end
            end

            if (cdb_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (rs_entries[i].busy) begin
                        if (!rs_entries[i].V_j && (rs_entries[i].Qj[3:0] == cdb_rob_tag)) begin
                            rs_entries[i].V_j <= 1'b1;
                            rs_entries[i].Qj  <= cdb_value;
                        end
                        if (!rs_entries[i].V_k && (rs_entries[i].Qk[3:0] == cdb_rob_tag)) begin
                            rs_entries[i].V_k <= 1'b1;
                            rs_entries[i].Qk  <= cdb_value;
                        end
                    end
                end
            end

            if (fu_issue_en) begin
                rs_entries[issued_rs_idx].busy <= 1'b0;
            end
        end
    end
endmodule

module alu_top (
    input clk,
    input reset,
    input [7:0]  fu_issue_opcode,
    input [31:0] fu_issue_operand1,
    input [31:0] fu_issue_operand2,
    input [4:0]  fu_issue_dest_reg,
    input [3:0]  fu_issue_rob_idx,
    input        fu_issue_en,

    output logic [31:0] cdb_result_value,
    output logic [3:0]  cdb_result_rob_tag,
    output logic        cdb_result_valid,

    output logic fu_add_sub_busy,
    output logic fu_logical_busy,
    output logic fu_shift_busy,
    output logic fu_rotate_busy,
    output logic fu_inc_dec_busy,
    output logic fu_abs_busy,
    output logic fu_compare_busy
);
    import config_pkg::*;

    logic [31:0] add_sub_result, logical_result, shift_result, rotate_result;
    logic [31:0] inc_dec_result, abs_result, compare_result;

    logic add_sub_done, logical_done, shift_done, rotate_done;
    logic inc_dec_done, abs_done, compare_done;

    logic [3:0] add_sub_rob_idx_out, logical_rob_idx_out;
    logic [3:0] shift_rob_idx_out, rotate_rob_idx_out;
    logic [3:0] inc_dec_rob_idx_out, abs_rob_idx_out, compare_rob_idx_out;

    logic add_sub_en, logical_en, shift_en, rotate_en;
    logic inc_dec_en, abs_en, compare_en;

    assign add_sub_en = fu_issue_en && (fu_issue_opcode[7:5] == FU_ADD_SUB);
    assign logical_en = fu_issue_en && (fu_issue_opcode[7:5] == FU_LOGICAL);
    assign shift_en   = fu_issue_en && (fu_issue_opcode[7:5] == FU_SHIFT);
    assign rotate_en  = fu_issue_en && (fu_issue_opcode[7:5] == FU_ROTATE);
    assign inc_dec_en = fu_issue_en && (fu_issue_opcode[7:5] == FU_INC_DEC);
    assign abs_en     = fu_issue_en && (fu_issue_opcode == OPCODE_ABS);
    assign compare_en = fu_issue_en && (fu_issue_opcode == OPCODE_COMPARE);

    add_sub_fu u_add_sub_fu (
        .a(fu_issue_operand1), .b(fu_issue_operand2), .clock(clk), .reset(reset),
        .op(fu_issue_opcode[0]), .en(add_sub_en), .rob_idx_in(fu_issue_rob_idx),
        .result(add_sub_result), .done(add_sub_done), .rob_idx_out(add_sub_rob_idx_out),
        .busy(fu_add_sub_busy)
    );

    logica_fu u_logical_fu (
        .a(fu_issue_operand1), .b(fu_issue_operand2), .op(fu_issue_opcode[1:0]),
        .reset(reset), .clock(clk), .en(logical_en), .rob_idx_in(fu_issue_rob_idx),
        .result(logical_result), .done(logical_done), .rob_idx_out(logical_rob_idx_out),
        .busy(fu_logical_busy)
    );

    shift_fu u_shift_fu (
        .a(fu_issue_operand1), .reset(reset), .clk(clk),
        .op(fu_issue_opcode[0]), .en(shift_en), .rob_idx_in(fu_issue_rob_idx),
        .result(shift_result), .done(shift_done), .rob_idx_out(shift_rob_idx_out),
        .busy(fu_shift_busy)
    );

    rotate_fu u_rotate_fu (
        .a(fu_issue_operand1), .reset(reset), .clock(clk),
        .op(fu_issue_opcode[0]), .en(rotate_en), .rob_idx_in(fu_issue_rob_idx),
        .result(rotate_result), .done(rotate_done), .rob_idx_out(rotate_rob_idx_out),
        .busy(fu_rotate_busy)
    );

    increment_decrement_fu u_inc_dec_fu (
        .a(fu_issue_operand1), .op(fu_issue_opcode[0]), .clock(clk), .reset(reset),
        .en(inc_dec_en), .rob_idx_in(fu_issue_rob_idx),
        .result(inc_dec_result), .done(inc_dec_done), .rob_idx_out(inc_dec_rob_idx_out),
        .busy(fu_inc_dec_busy)
    );

    abs_fu u_abs_fu (
        .clock(clk), .reset(reset), .a(fu_issue_operand1), .en(abs_en),
        .rob_idx_in(fu_issue_rob_idx), .result(abs_result), .done(abs_done),
        .rob_idx_out(abs_rob_idx_out), .busy(fu_abs_busy)
    );

    compare_fu u_compare_fu (
        .a(fu_issue_operand1), .b(fu_issue_operand2), .clock(clk), .reset(reset),
        .en(compare_en), .rob_idx_in(fu_issue_rob_idx),
        .result(compare_result), .done(compare_done), .rob_idx_out(compare_rob_idx_out),
        .busy(fu_compare_busy)
    );

    always_comb begin
        cdb_result_valid = 1'b0;
        cdb_result_value = 32'b0;
        cdb_result_rob_tag = 4'b0;

        if (add_sub_done) begin
            cdb_result_valid = 1'b1; cdb_result_value = add_sub_result; cdb_result_rob_tag = add_sub_rob_idx_out;
        end else if (logical_done) begin
            cdb_result_valid = 1'b1; cdb_result_value = logical_result; cdb_result_rob_tag = logical_rob_idx_out;
        end else if (shift_done) begin
            cdb_result_valid = 1'b1; cdb_result_value = shift_result; cdb_result_rob_tag = shift_rob_idx_out;
        end else if (rotate_done) begin
            cdb_result_valid = 1'b1; cdb_result_value = rotate_result; cdb_result_rob_tag = rotate_rob_idx_out;
        end else if (inc_dec_done) begin
            cdb_result_valid = 1'b1; cdb_result_value = inc_dec_result; cdb_result_rob_tag = inc_dec_rob_idx_out;
        end else if (abs_done) begin
            cdb_result_valid = 1'b1; cdb_result_value = abs_result; cdb_result_rob_tag = abs_rob_idx_out;
        end else if (compare_done) begin
            cdb_result_valid = 1'b1; cdb_result_value = compare_result; cdb_result_rob_tag = compare_rob_idx_out;
        end
    end
endmodule
// --- Start of Functional Units (FU) with corrected headers ---
module add_sub_fu (input [31:0] a, input [31:0] b, input clock, input reset, input op, input en, input [3:0] rob_idx_in, output logic [31:0] result, output logic done, output logic [3:0] rob_idx_out, output logic busy);
    reg [31:0] a_reg, b_reg; reg op_reg; reg [3:0] rob_idx_reg; reg state;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; result <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin a_reg <= a; b_reg <= b; op_reg <= op; rob_idx_reg <= rob_idx_in; state <= 1; busy <= 1; end
            else if (state == 1) begin result <= op_reg ? (a_reg - b_reg) : (a_reg + b_reg); rob_idx_out <= rob_idx_reg; done <= 1; busy <= 0; state <= 0; end
        end
    end
endmodule

module logica_fu (input [31:0] a, input [31:0] b, input [1:0] op, input reset, input clock, input en, input [3:0] rob_idx_in, output logic [31:0] result, output logic done, output logic [3:0] rob_idx_out, output logic busy);
    reg [31:0] a_reg, b_reg; reg [1:0] op_reg; reg [3:0] rob_idx_reg; reg state;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin a_reg <= a; b_reg <= b; op_reg <= op; rob_idx_reg <= rob_idx_in; state <= 1; busy <= 1; end
            else if (state == 1) begin
                case(op_reg) 2'b00: result<=a_reg&b_reg; 2'b01: result<=a_reg|b_reg; 2'b10: result<=a_reg^b_reg; 2'b11: result<=~a_reg; endcase
                rob_idx_out <= rob_idx_reg; done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

module shift_fu (input [31:0] a, input reset, input clk, input op, input en, input [3:0] rob_idx_in, output logic [31:0] result, output logic done, output logic [3:0] rob_idx_out, output logic busy);
    reg [31:0] a_reg; reg op_reg; reg [3:0] rob_idx_reg; reg state;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin a_reg <= a; op_reg <= op; rob_idx_reg <= rob_idx_in; state <= 1; busy <= 1; end
            else if (state == 1) begin result <= op_reg ? (a_reg >> 1) : (a_reg << 1); rob_idx_out <= rob_idx_reg; done <= 1; busy <= 0; state <= 0; end
        end
    end
endmodule

module rotate_fu (input [31:0] a, input reset, input clock, input op, input en, input [3:0] rob_idx_in, output logic [31:0] result, output logic done, output logic [3:0] rob_idx_out, output logic busy);
    reg [31:0] a_reg; reg op_reg; reg [3:0] rob_idx_reg; reg state;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin a_reg <= a; op_reg <= op; rob_idx_reg <= rob_idx_in; state <= 1; busy <= 1; end
            else if (state == 1) begin result <= op_reg ? {a_reg[0], a_reg[31:1]} : {a_reg[30:0], a_reg[31]}; rob_idx_out <= rob_idx_reg; done <= 1; busy <= 0; state <= 0; end
        end
    end
endmodule

module increment_decrement_fu (input [31:0] a, input op, input clock, input reset, input en, input [3:0] rob_idx_in, output logic [31:0] result, output logic done, output logic [3:0] rob_idx_out, output logic busy);
    reg [31:0] a_reg; reg op_reg; reg [3:0] rob_idx_reg; reg state;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin a_reg <= a; op_reg <= op; rob_idx_reg <= rob_idx_in; state <= 1; busy <= 1; end
            else if (state == 1) begin result <= op_reg ? (a_reg - 1) : (a_reg + 1); rob_idx_out <= rob_idx_reg; done <= 1; busy <= 0; state <= 0; end
        end
    end
endmodule

module abs_fu (input clock, input reset, input [31:0] a, input en, input [3:0] rob_idx_in, output logic [31:0] result, output logic done, output logic [3:0] rob_idx_out, output logic busy);
    reg [31:0] a_reg; reg [3:0] rob_idx_reg; reg state;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin a_reg <= a; rob_idx_reg <= rob_idx_in; state <= 1; busy <= 1; end
            else if (state == 1) begin result <= a_reg[31] ? (~a_reg + 1) : a_reg; rob_idx_out <= rob_idx_reg; done <= 1; busy <= 0; state <= 0; end
        end
    end
endmodule

module compare_fu (input [31:0] a, input [31:0] b, input clock, input reset, input en, input [3:0] rob_idx_in, output logic [31:0] result, output logic done, output logic [3:0] rob_idx_out, output logic busy);
    reg [31:0] a_reg, b_reg; reg [3:0] rob_idx_reg; reg state;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            done <= 0;
            if (state == 0 && en) begin a_reg <= a; b_reg <= b; rob_idx_reg <= rob_idx_in; state <= 1; busy <= 1; end
            else if (state == 1) begin
                if ($signed(a_reg) > $signed(b_reg)) result <= 32'd1;
                else if ($signed(a_reg) < $signed(b_reg)) result <= -32'd1;
                else result <= 32'd0;
                rob_idx_out <= rob_idx_reg; done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule