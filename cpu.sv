`timescale 1ns / 1ps
import config_pkg::*;
import cpu_types_pkg::*;

module cpu (
    input  wire logic        clock,
    input  wire logic        reset,
    input  wire logic        ext_pc_set,
    input  wire logic [9:0]  ext_pc_val,
    output wire logic [9:0]  current_pc_out,
    output wire logic [31:0] alu_result 
);

    logic pipeline_flush, rob_full, rename_stall, renamed_valid;
    logic dispatch_success; 
    logic [31:0] redirect_pc;
    logic [9:0]  id_pc;
    logic        id_valid, rob_alloc_valid, commit_retire_en, commit_valid;
    logic [4:0]  rob_next_idx, rob_head_tag;
    
    logic [41:0] iq_in_packet, iq_out_packet;
    logic        iq_enq_v, iq_deq_v, iq_full;

    logic        cdb_valid;
    logic [4:0]  cdb_tag;
    logic [31:0] cdb_val;
    logic        alu_cdb_v, lsu_cdb_v, branch_cdb_v;
    logic [4:0]  alu_cdb_t, lsu_cdb_t, branch_cdb_t;
    logic [31:0] alu_cdb_d, lsu_cdb_d, branch_cdb_d;

    rs_status_t [7:0] alu_rs_status_packed;
    rs_status_t       alu_rs_status_unpacked [7:0];
    logic [7:0]       alu_issue_en_bus;
    
    logic [7:0]  fu_alu_opcode, fu_br_opcode;
    logic [31:0] fu_alu_op1, fu_alu_op2, fu_br_op1, fu_br_op2, fu_br_pc;
    logic [7:0]  fu_br_imm;
    logic [4:0]  fu_alu_rd, fu_alu_tag, fu_br_tag;
    logic        fu_alu_en, fu_br_en;
    logic        f_add_b, f_log_b, f_shf_b, f_rot_b, f_inc_b, f_abs_b, f_cmp_b, f_br_busy;

    logic [9:0]  instr_mem_addr, data_mem_addr;
    logic [31:0] instr_mem_data, data_mem_wdata, data_mem_rdata;
    logic        instr_mem_valid, data_mem_valid, instr_pc_req, data_mem_req, data_mem_rw, rf_wen;
    logic [4:0]  rf_raddr1, rf_raddr2, rf_waddr;
    logic [31:0] rf_rdata1, rf_rdata2, rf_wdata;

    logic alu_rs_full, branch_rs_full, lsq_rs_full, to_alu_v, to_lsu_v, to_br_v;
    alu_dispatch_packet_t    to_alu_packet;
    lsu_dispatch_packet_t    to_lsu_packet;
    branch_dispatch_packet_t to_branch_packet;
    
    decoded_instruction_t    decode_inst;
    renamed_instruction_t    renamed_inst;
    rob_instruction_metadata_t rob_alloc_metadata;
    rob_entry_t              commit_data;

    always_comb begin
        for (int i = 0; i < 8; i++) alu_rs_status_packed[i] = alu_rs_status_unpacked[i];
        
        cdb_valid = 1'b0; cdb_tag = 5'd0; cdb_val = 32'd0;
        if (lsu_cdb_v) begin 
            cdb_valid = 1'b1; cdb_tag = lsu_cdb_t; cdb_val = lsu_cdb_d; 
        end else if (branch_cdb_v) begin 
            cdb_valid = 1'b1; cdb_tag = branch_cdb_t; cdb_val = branch_cdb_d; 
        end else if (alu_cdb_v) begin 
            cdb_valid = 1'b1; cdb_tag = alu_cdb_t; cdb_val = alu_cdb_d; 
        end
    end

    assign current_pc_out = id_pc;
    assign alu_result     = (commit_valid) ? commit_data.result_value : 32'b0;

    i_f u_fetch (
        .clock, .reset, 
        .stall(rob_full || rename_stall), 
        .branch_taken(pipeline_flush), 
        .branch_target(redirect_pc[9:0]), 
        .instruction_mem_data(instr_mem_data), 
        .instruction_valid(instr_mem_valid), 
        .queue_full(iq_full),
        .enqueue_valid(iq_enq_v),
        .fetch_packet_o(iq_in_packet),
        .start_fetch(instr_pc_req), 
        .pc_to_reader(instr_mem_addr), 
        .ext_pc_set, .ext_pc_val
    );

    instruction_queue u_iq (
        .clk(clock), .reset,
        .enqueue_valid(iq_enq_v),
        .enqueue_data(iq_in_packet),
        .dequeue_valid(iq_deq_v),
        .dequeue_data(iq_out_packet),
        .dequeue_request(dispatch_success), 
        .queue_full(iq_full),
        .queue_occupancy()
    );

    id u_decode (
        .clock, .reset, 
        .if_id_pc(iq_out_packet[41:32]), 
        .if_id_opcode(iq_out_packet[31:0]), 
        .stall(rob_full || rename_stall), 
        .flush(pipeline_flush), 
        .dispatch_success_i(dispatch_success), 
        .id_valid, .id_pc, .decoded_instruction(decode_inst)
    );
    
    rename_stage u_rename (
        .clk(clock), .reset, .flush_i(pipeline_flush), 
        .id_valid_i(id_valid), .decode_inst_i(decode_inst), .decode_pc_i(id_pc), 
        .rob_next_idx_i(rob_next_idx), 
        .commit_valid_i(commit_retire_en), .commit_instr_i(commit_data.inst_data), .commit_rob_idx_i(rob_head_tag), 
        .rename_stall_i(rename_stall), 
        .dispatch_success_i(dispatch_success), 
        .renamed_valid_o(renamed_valid), .renamed_inst_o(renamed_inst), .rename_busy_o()
    );
    
    dispatch_stage u_dispatch (
        .clk(clock), .reset, .flush_i(pipeline_flush), 
        .renamed_valid_i(renamed_valid), .renamed_inst_i(renamed_inst), 
        .rf_raddr1_o(rf_raddr1), .rf_raddr2_o(rf_raddr2), 
        .rf_rdata1_i(rf_rdata1), .rf_rdata2_i(rf_rdata2), 
        .commit_wen_i(rf_wen), .commit_waddr_i(rf_waddr), .commit_wdata_i(rf_wdata), 
        .rob_full_i(rob_full), .alu_rs_full_i(alu_rs_full), .lsq_rs_full_i(lsq_rs_full), .branch_rs_full_i(branch_rs_full), 
        .lsq_next_idx_i(4'd0), 
        .dispatch_success_o(dispatch_success), 
        .rename_stall_o(rename_stall), 
        .rob_allocate_valid_o(rob_alloc_valid), .rob_allocate_data_o(rob_alloc_metadata), 
        .to_alu_valid_o(to_alu_v), .to_alu_packet_o(to_alu_packet), 
        .to_lsu_valid_o(to_lsu_v), .to_lsu_packet_o(to_lsu_packet), 
        .to_branch_valid_o(to_br_v), .to_branch_packet_o(to_branch_packet)
    );

    issue_stage u_issue (
        .clk(clock), .reset, 
        .alu_rs_status_i(alu_rs_status_packed), 
        .alu_rs_issue_en_o(alu_issue_en_bus)
    );
    
    reservation_station u_alu_rs (
        .clk(clock), .reset, 
        .rs_dispatch_valid(to_alu_v), .rs_dispatch_data(to_alu_packet), .rs_full_out(alu_rs_full), 
        .cdb_valid(cdb_valid), .cdb_rob_tag(cdb_tag), .cdb_value(cdb_val), 
        .fu_issue_opcode(fu_alu_opcode), .fu_issue_operand1(fu_alu_op1), .fu_issue_operand2(fu_alu_op2), 
        .fu_issue_dest_reg(fu_alu_rd), .fu_issue_rob_idx(fu_alu_tag), .fu_issue_en(fu_alu_en), 
        .rs_status_out(alu_rs_status_unpacked), .rs_issue_en_in(alu_issue_en_bus), 
        .fu_add_sub_busy(f_add_b), .fu_logical_busy(f_log_b), .fu_shift_busy(f_shf_b), 
        .fu_rotate_busy(f_rot_b), .fu_inc_dec_busy(f_inc_b), .fu_abs_busy(f_abs_b), .fu_compare_busy(f_cmp_b), 
        .rs_allocated_idx()
    );
    
    alu_top u_alu_top (
        .clk(clock), .reset, 
        .fu_issue_opcode(fu_alu_opcode), .fu_issue_operand1(fu_alu_op1), .fu_issue_operand2(fu_alu_op2), 
        .fu_issue_dest_reg(fu_alu_rd), .fu_issue_rob_idx(fu_alu_tag), .fu_issue_en(fu_alu_en), 
        .cdb_result_value(alu_cdb_d), .cdb_result_rob_tag(alu_cdb_t), .cdb_result_valid(alu_cdb_v), 
        .fu_add_sub_busy(f_add_b), .fu_logical_busy(f_log_b), .fu_shift_busy(f_shf_b), 
        .fu_rotate_busy(f_rot_b), .fu_inc_dec_busy(f_inc_b), .fu_abs_busy(f_abs_b), .fu_compare_busy(f_cmp_b)
    );
    
    branch_reservation_station u_br_rs (
        .clock(clock), .reset, 
        .rs_dispatch_valid(to_br_v), .rs_dispatch_data(to_branch_packet), .rs_full_out(branch_rs_full), 
        .fu_issue_en(fu_br_en), .fu_issue_opcode(fu_br_opcode), .fu_issue_operand1(fu_br_op1), 
        .fu_issue_operand2(fu_br_op2), .fu_issue_rob_idx(fu_br_tag), .fu_issue_pc(fu_br_pc), 
        .fu_issue_imm(fu_br_imm), 
        .cdb_valid(cdb_valid), .cdb_rob_tag(cdb_tag), .cdb_value(cdb_val), .fu_branch_busy(f_br_busy), 
        .rs_allocated_idx()
    );
    
    branch_unit u_br_fu (
        .clock(clock), .reset, 
        .fu_issue_en(fu_br_en), .fu_issue_opcode(fu_br_opcode), .fu_issue_operand1(fu_br_op1), 
        .fu_issue_operand2(fu_br_op2), .fu_issue_pc(fu_br_pc), .fu_issue_imm(fu_br_imm), 
        .fu_issue_rob_idx(fu_br_tag), 
        .branch_cdb_valid(branch_cdb_v), .branch_cdb_tag(branch_cdb_t), .branch_cdb_val(branch_cdb_d), 
        .busy(f_br_busy)
    );
    
    load_store_unit u_lsu (
        .clock(clock), .reset, 
        .lsu_dispatch_valid(to_lsu_v), .lsu_packet_i(to_lsu_packet), 
        .lsu_cdb_valid(lsu_cdb_v), .lsu_cdb_rob_tag(lsu_cdb_t), .lsu_cdb_value(lsu_cdb_d), 
        .data_mem_addr(data_mem_addr), .data_mem_write_data(data_mem_wdata), 
        .data_mem_read_write(data_mem_rw), .data_mem_req(data_mem_req), 
        .data_mem_data_i(data_mem_rdata), .data_mem_valid(data_mem_valid), 
        .rs_full_o(lsq_rs_full)
    );

    rob u_rob (
        .clk(clock), .reset,
        .pipeline_flush_i(pipeline_flush),
        .rob_allocate_valid_i(rob_alloc_valid),
        .rob_allocate_data_i(rob_alloc_metadata),
        .wb_valid_i(cdb_valid),
        .wb_rob_tag_i(cdb_tag),
        .wb_result_val_i(cdb_val),
        .wb_branch_mispredict_i(branch_cdb_v && branch_cdb_d[0]), 
        .commit_ready_i(commit_retire_en),
        .rob_full_o(rob_full),
        .rob_next_idx_o(rob_next_idx),
        .commit_valid_o(commit_valid),
        .commit_data_o(commit_data),
        .head_ptr_o(rob_head_tag),
        .flush_o(pipeline_flush),
        .flush_pc_o(redirect_pc)
    );

    commit_stage u_commit (
        .clock(clock), .reset,
        .rob_head_entry_i(commit_data),
        .rob_empty_i(!commit_valid),
        .lsq_ready_to_commit_i(1'b1),
        .reg_write_en_o(rf_wen),
        .reg_write_addr_o(rf_waddr),
        .reg_write_data_o(rf_wdata),
        .commit_en_o(commit_retire_en)
    );
    
    register u_regfile (
        .clock(clock), .reset, 
        .read_en(1'b1), 
        .read_addr1(rf_raddr1), .read_addr2(rf_raddr2), .read_data1(rf_rdata1), .read_data2(rf_rdata2), 
        .write_enable(rf_wen), .write(rf_waddr), .write_data(rf_wdata)
    );

    memory u_memory (
        .clock(clock), .reset, 
        .pc_en(instr_pc_req), .pc_addr(instr_mem_addr), .pc_instr_out(instr_mem_data), .pc_done(instr_mem_valid), 
        .data_en(data_mem_req), .data_rw(data_mem_rw), .data_addr(data_mem_addr), 
        .data_wdata(data_mem_wdata), .data_out(data_mem_rdata), .data_done(data_mem_valid)
    );

endmodule
