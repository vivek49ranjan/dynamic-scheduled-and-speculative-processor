
module alu_top (
    input  logic         clk, reset,
    
    input  logic [7:0]   fu_issue_opcode,
    input  logic [31:0]  fu_issue_operand1,
    input  logic [31:0]  fu_issue_operand2,
    input  logic [4:0]   fu_issue_dest_reg, 
    input  logic [4:0]   fu_issue_rob_idx,
    input  logic         fu_issue_en,

    output logic [31:0]  cdb_result_value,
    output logic [4:0]   cdb_result_rob_tag,
    output logic [4:0]   cdb_dest_reg,       
    output logic         cdb_result_valid,

    output logic fu_add_sub_busy, fu_logical_busy, fu_shift_busy, fu_compare_busy
);

    logic [31:0] res_add, res_log, res_shf, res_cmp;
    logic [4:0]  tag_add, tag_log, tag_shf, tag_cmp;
    logic [4:0]  dst_add, dst_log, dst_shf, dst_cmp;
    logic        v_add, v_log, v_shf, v_cmp;

    logic ack_add, ack_log, ack_shf, ack_cmp;

    add_sub_fu u_add_sub_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b000)),
        .a(fu_issue_operand1), .b(fu_issue_operand2), .op(fu_issue_opcode[0]),
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_add_sub_busy), .ack(ack_add), 
        .result(res_add), .rob_idx_out(tag_add), .dest_reg_out(dst_add), .done(v_add)
    );

    logica_fu u_logical_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b011)),
        .a(fu_issue_operand1), .b(fu_issue_operand2), .op(fu_issue_opcode[1:0]),
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_logical_busy), .ack(ack_log), // Added ack
        .result(res_log), .rob_idx_out(tag_log), .dest_reg_out(dst_log), .done(v_log)
    );

    shift_fu u_shift_fu (
        .clk(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode[7:5] == 3'b100)),
        .a(fu_issue_operand1), .shamt(fu_issue_operand2[4:0]), .op(fu_issue_opcode[1:0]),     
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_shift_busy), .ack(ack_shf), // Added ack
        .result(res_shf), .rob_idx_out(tag_shf), .dest_reg_out(dst_shf), .done(v_shf)
    );

    compare_fu u_compare_fu (
        .clock(clk), .reset(reset), 
        .en(fu_issue_en && (fu_issue_opcode == OPCODE_COMPARE)),
        .a(fu_issue_operand1), .b(fu_issue_operand2), 
        .rob_idx_in(fu_issue_rob_idx), .dest_reg_in(fu_issue_dest_reg),
        .busy(fu_compare_busy), .ack(ack_cmp), // Added ack
        .result(res_cmp), .rob_idx_out(tag_cmp), .dest_reg_out(dst_cmp), .done(v_cmp)
    );

    logic [1:0] rr_cdb_ptr;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rr_cdb_ptr <= 2'd0;
        end else if (cdb_result_valid) begin
            rr_cdb_ptr <= rr_cdb_ptr + 2'd1;
        end
    end

    always_comb begin
        cdb_result_valid   = 1'b0; 
        cdb_result_value   = 32'd0; 
        cdb_result_rob_tag = 5'd0; 
        cdb_dest_reg       = 5'd0;
        ack_add = 1'b0; ack_log = 1'b0; ack_shf = 1'b0; ack_cmp = 1'b0;

        for (int i = 0; i < 4; i++) begin
            logic [1:0] check_idx;
            check_idx = rr_cdb_ptr + i[1:0];

            if (!cdb_result_valid) begin
                case (check_idx)
                    2'd0: if (v_add) begin 
                            cdb_result_valid = 1'b1; cdb_result_value = res_add; 
                            cdb_result_rob_tag = tag_add; cdb_dest_reg = dst_add; ack_add = 1'b1; 
                          end
                    2'd1: if (v_log) begin 
                            cdb_result_valid = 1'b1; cdb_result_value = res_log; 
                            cdb_result_rob_tag = tag_log; cdb_dest_reg = dst_log; ack_log = 1'b1; 
                          end
                    2'd2: if (v_shf) begin 
                            cdb_result_valid = 1'b1; cdb_result_value = res_shf; 
                            cdb_result_rob_tag = tag_shf; cdb_dest_reg = dst_shf; ack_shf = 1'b1; 
                          end
                    2'd3: if (v_cmp) begin 
                            cdb_result_valid = 1'b1; cdb_result_value = res_cmp; 
                            cdb_result_rob_tag = tag_cmp; cdb_dest_reg = dst_cmp; ack_cmp = 1'b1; 
                          end
                endcase
            end
        end
    end
endmodule


module shift_fu (
    input  logic [31:0] a,
    input  logic [4:0]  shamt,       
    input  logic [1:0]  op,          
    input  logic        reset, clk, en, ack,
    input  logic [4:0]  rob_idx_in, dest_reg_in,
    output logic [31:0] result,
    output logic        done, busy,
    output logic [4:0]  rob_idx_out, dest_reg_out
);
    logic [31:0] a_reg;
    logic [4:0]  shamt_reg;
    logic [1:0]  op_reg;
    logic [4:0]  rob_reg, dest_reg;
    logic        state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin state <= 0; done <= 0; busy <= 0; end
        else begin
            if (ack) done <= 1'b0; 
            
            if (state == 0 && en) begin
                a_reg <= a; shamt_reg <= shamt; op_reg <= op;
                rob_reg <= rob_idx_in; dest_reg <= dest_reg_in;
                state <= 1; busy <= 1;
            end else if (state == 1) begin
                case(op_reg)
                    2'b00:   result <= a_reg << shamt_reg;                
                    2'b01:   result <= a_reg >> shamt_reg;                
                    2'b10:   result <= $signed(a_reg) >>> shamt_reg;      
                    default: result <= a_reg;
                endcase
                rob_idx_out <= rob_reg; dest_reg_out <= dest_reg;
                done <= 1; busy <= 0; state <= 0;
            end
        end
    end
endmodule

module add_sub_fu (
    input  logic [31:0] a, b, 
    input  logic clock, reset, en, op, ack, 
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
            if (ack) done <= 1'b0; 
            
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

module logica_fu (
    input  logic [31:0] a, b, 
    input  logic [1:0]  op, 
    input  logic reset, clock, en, ack, 
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
            if (ack) done <= 1'b0; 
            
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

module rotate_fu (
    input  logic [31:0] a, 
    input  logic reset, clock, en, op, ack,
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
            if (ack) done <= 1'b0;
            
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

module increment_decrement_fu (
    input  logic [31:0] a, 
    input  logic op, clock, reset, en, ack,
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
            if (ack) done <= 1'b0;
            
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

module abs_fu (
    input  logic clock, reset, en, ack,
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
            if (ack) done <= 1'b0;
            
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

module compare_fu (
    input  logic [31:0] a, b, 
    input  logic clock, reset, en, ack,
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
            if (ack) done <= 1'b0; 
            
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
