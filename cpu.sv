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

    logic        bp_train_en;
    logic [9:0]  bp_train_pc;
    logic        bp_train_taken;
    logic [9:0]  bp_train_target;
    
    logic        fetch_pred_taken;
    logic [9:0]  fetch_pred_target;
    logic        branch_won_cdb;

    typedef struct packed {
        logic [4:0]  tag;
        logic [31:0] val;
        logic        is_branch;
        logic        mispredict;
    } cdb_packet_t;

    cdb_packet_t cdb_fifo [0:31];
    logic [4:0] cdb_head, cdb_tail;
    logic [5:0] cdb_count;
    logic [1:0] push_amt;

    logic actual_taken, predicted_taken, is_mispredict;
    logic [9:0] actual_target, predicted_target;
    logic [10:0] rob_predictions [0:31];

    assign actual_taken = branch_cdb_d[10];
    assign actual_target = branch_cdb_d[9:0];
    assign predicted_taken = rob_predictions[branch_cdb_t][10];
    assign predicted_target = rob_predictions[branch_cdb_t][9:0];
    assign is_mispredict = (actual_taken != predicted_taken) || (actual_taken && (actual_target != predicted_target));

    assign push_amt = {1'b0, alu_cdb_v} + {1'b0, lsu_cdb_v} + {1'b0, branch_cdb_v};

   always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            cdb_head <= 5'd0;
            cdb_tail <= 5'd0;
            cdb_count <= 6'd0;
            for (int i=0; i<32; i++) cdb_fifo[i] <= '0;
        end else if (pipeline_flush) begin
            cdb_head <= 5'd0;
            cdb_tail <= 5'd0;
            cdb_count <= 6'd0;
            for (int i=0; i<32; i++) cdb_fifo[i] <= '0;
        end else begin
            // Pointer Math
            if (cdb_count > 0) begin
                cdb_head <= cdb_head + 1;
                cdb_count <= cdb_count - 1 + push_amt;
            end else begin
                cdb_count <= cdb_count + push_amt;
            end
            
            cdb_tail <= cdb_tail + push_amt;

            if (alu_cdb_v) begin
                cdb_fifo[cdb_tail].tag <= alu_cdb_t;
                cdb_fifo[cdb_tail].val <= alu_cdb_d;
                cdb_fifo[cdb_tail].is_branch <= 1'b0;
                cdb_fifo[cdb_tail].mispredict <= 1'b0;
            end
            if (lsu_cdb_v) begin
                cdb_fifo[cdb_tail + alu_cdb_v].tag <= lsu_cdb_t;
                cdb_fifo[cdb_tail + alu_cdb_v].val <= lsu_cdb_d;
                cdb_fifo[cdb_tail + alu_cdb_v].is_branch <= 1'b0;
                cdb_fifo[cdb_tail + alu_cdb_v].mispredict <= 1'b0;
            end
            if (branch_cdb_v) begin
                cdb_fifo[cdb_tail + alu_cdb_v + lsu_cdb_v].tag <= branch_cdb_t;
                cdb_fifo[cdb_tail + alu_cdb_v + lsu_cdb_v].val <= branch_cdb_d;
                cdb_fifo[cdb_tail + alu_cdb_v + lsu_cdb_v].is_branch <= 1'b1;
                cdb_fifo[cdb_tail + alu_cdb_v + lsu_cdb_v].mispredict <= is_mispredict;
            end
        end
    end
    assign cdb_valid = (cdb_count > 0);
    assign cdb_tag   = cdb_fifo[cdb_head].tag;
    assign cdb_val   = cdb_fifo[cdb_head].val;
    assign branch_won_cdb = (cdb_count > 0) && cdb_fifo[cdb_head].is_branch;
    logic buffered_mispredict;
    assign buffered_mispredict = (cdb_count > 0) && cdb_fifo[cdb_head].mispredict;

    always_comb begin
        for (int i = 0; i < 8; i++) alu_rs_status_packed[i] = alu_rs_status_unpacked[i];

        bp_train_en = commit_valid && commit_retire_en && (commit_data.inst_data.instr_type == INSTR_BRANCH);
        bp_train_pc = commit_data.inst_data.pc[9:0];
        bp_train_target = commit_data.result_value[9:0];
        bp_train_taken = (commit_data.result_value[9:0] != (commit_data.inst_data.pc[9:0] + 10'd1));
    end

    assign current_pc_out = id_pc;
    assign alu_result     = (commit_valid) ? commit_data.result_value : 32'b0;

    logic [10:0] pred_queue [0:63]; 
    logic [5:0] pq_head, pq_tail;
    logic pq_deq;
    
    assign pq_deq = iq_deq_v && !(rob_full || rename_stall) && !pipeline_flush;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            pq_head <= 6'd0;
            pq_tail <= 6'd0;
        end else if (pipeline_flush) begin
            pq_head <= 6'd0;
            pq_tail <= 6'd0;
        end else begin
            if (iq_enq_v) begin
                pred_queue[pq_tail] <= {fetch_pred_taken, fetch_pred_target};
                pq_tail <= pq_tail + 6'd1;
            end
            if (pq_deq) begin
                pq_head <= pq_head + 6'd1;
            end
        end
    end

    logic dec_pred_taken;
    logic [9:0] dec_pred_target;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            dec_pred_taken <= 1'b0;
            dec_pred_target <= 10'd0;
        end else if (pipeline_flush) begin
            dec_pred_taken <= 1'b0;
            dec_pred_target <= 10'd0;
        end else if (pq_deq && (iq_out_packet[31:0] != 32'd0)) begin 
            dec_pred_taken <= pred_queue[pq_head][10];
            dec_pred_target <= pred_queue[pq_head][9:0];
        end
    end

    always_ff @(posedge clock) begin
        if (rob_alloc_valid) begin
            rob_predictions[rob_next_idx] <= {dec_pred_taken, dec_pred_target};
        end
    end


    i_f u_fetch (
        .clock(clock), .reset(reset), 
        .stall(rob_full || rename_stall), 
        .flush_en(pipeline_flush), 
        .flush_target(redirect_pc[9:0]), 
        .bp_train_en(bp_train_en), .bp_train_pc(bp_train_pc),
        .bp_train_taken(bp_train_taken), .bp_train_target(bp_train_target),
        .instruction_mem_data(instr_mem_data), 
        .instruction_valid(instr_mem_valid), 
        .queue_full(iq_full), .enqueue_valid(iq_enq_v),
        .fetch_packet_o(iq_in_packet),
        .predict_taken_o(fetch_pred_taken), .predict_target_o(fetch_pred_target),    
        .start_fetch(instr_pc_req), .pc_to_reader(instr_mem_addr), 
        .ext_pc_set(ext_pc_set), .ext_pc_val(ext_pc_val)
    );

    instruction_queue u_iq (
        .clk(clock), .reset(reset | pipeline_flush), 
        .enqueue_valid(iq_enq_v), .enqueue_data(iq_in_packet),
        .dequeue_valid(iq_deq_v), .dequeue_data(iq_out_packet),
        .dequeue_request(pq_deq), .queue_full(iq_full), .queue_occupancy()
    );

    decode u_decode (
        .clock(clock), .reset(reset), 
        .if_id_valid(iq_deq_v), .if_id_pc(iq_out_packet[41:32]), .if_id_opcode(iq_out_packet[31:0]), 
        .stall(rob_full || rename_stall), .flush(pipeline_flush), 
        .dispatch_success_i(dispatch_success), .id_valid(id_valid), .id_pc(id_pc), 
        .decoded_instruction(decode_inst)
    );
    
    rename_stage u_rename (
        .clk(clock), .reset(reset), .flush_i(pipeline_flush), 
        .id_valid_i(id_valid), .decode_inst_i(decode_inst), .decode_pc_i(id_pc), 
        .rob_next_idx_i(rob_next_idx), 
        .commit_valid_i(commit_retire_en), .commit_instr_i(commit_data.inst_data), .commit_rob_idx_i(rob_head_tag), 
        .rename_stall_i(rename_stall), .dispatch_success_i(dispatch_success), 
        .renamed_valid_o(renamed_valid), .renamed_inst_o(renamed_inst), .rename_busy_o()
    );
    
    dispatch_stage u_dispatch (
        .clk(clock), .reset(reset), .flush_i(pipeline_flush), 
        .renamed_valid_i(renamed_valid), .renamed_inst_i(renamed_inst), 
        .rf_raddr1_o(rf_raddr1), .rf_raddr2_o(rf_raddr2), .rf_rdata1_i(rf_rdata1), .rf_rdata2_i(rf_rdata2), 
        .commit_wen_i(rf_wen), .commit_waddr_i(rf_waddr), .commit_wdata_i(rf_wdata), 
        .rob_full_i(rob_full), .alu_rs_full_i(alu_rs_full), .lsq_rs_full_i(lsq_rs_full), .branch_rs_full_i(branch_rs_full), 
        .lsq_next_idx_i(4'd0), .dispatch_success_o(dispatch_success), .rename_stall_o(rename_stall), 
        .rob_allocate_valid_o(rob_alloc_valid), .rob_allocate_data_o(rob_alloc_metadata), 
        .to_alu_valid_o(to_alu_v), .to_alu_packet_o(to_alu_packet), 
        .to_lsu_valid_o(to_lsu_v), .to_lsu_packet_o(to_lsu_packet), 
        .to_branch_valid_o(to_br_v), .to_branch_packet_o(to_branch_packet)
    );

    issue_stage u_issue (
        .clk(clock), .reset(reset), .alu_rs_status_i(alu_rs_status_packed), .alu_rs_issue_en_o(alu_issue_en_bus)
    );
    
    reservation_station u_alu_rs (
        .clk(clock), .reset(reset), 
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
        .clk(clock), .reset(reset), 
        .fu_issue_opcode(fu_alu_opcode), .fu_issue_operand1(fu_alu_op1), .fu_issue_operand2(fu_alu_op2), 
        .fu_issue_dest_reg(fu_alu_rd), .fu_issue_rob_idx(fu_alu_tag), .fu_issue_en(fu_alu_en), 
        .cdb_result_value(alu_cdb_d), .cdb_result_rob_tag(alu_cdb_t), .cdb_result_valid(alu_cdb_v),
        .cdb_dest_reg(), 
        .fu_add_sub_busy(f_add_b), .fu_logical_busy(f_log_b), .fu_shift_busy(f_shf_b), .fu_compare_busy(f_cmp_b)
    );
    
    load_store_unit u_lsu (
        .clock(clock), .reset(reset), 
        .lsu_dispatch_valid(to_lsu_v), .lsu_packet_i(to_lsu_packet), 
        .cdb_valid_i(cdb_valid), .cdb_rob_tag_i(cdb_tag), .cdb_value_i(cdb_val),
        .lsu_cdb_valid(lsu_cdb_v), .lsu_cdb_rob_tag(lsu_cdb_t), .lsu_cdb_value(lsu_cdb_d), 
        .data_mem_addr(data_mem_addr), .data_mem_write_data(data_mem_wdata), 
        .data_mem_read_write(data_mem_rw), .data_mem_req(data_mem_req), 
        .data_mem_data_i(data_mem_rdata), .data_mem_valid(data_mem_valid), 
        .rs_full_o(lsq_rs_full)
    );
    
    branch_reservation_station u_br_rs (
        .clock(clock), .reset(reset), 
        .rs_dispatch_valid(to_br_v), .rs_dispatch_data(to_branch_packet), .rs_full_out(branch_rs_full), 
        .fu_issue_en(fu_br_en), .fu_issue_opcode(fu_br_opcode), .fu_issue_operand1(fu_br_op1), 
        .fu_issue_operand2(fu_br_op2), .fu_issue_rob_idx(fu_br_tag), .fu_issue_pc(fu_br_pc), .fu_issue_imm(fu_br_imm), 
        .cdb_valid(cdb_valid), .cdb_rob_tag(cdb_tag), .cdb_value(cdb_val), .fu_branch_busy(f_br_busy), 
        .rs_allocated_idx()
    );
    
    branch_unit u_br_fu (
        .clock(clock), .reset(reset), 
        .fu_issue_en(fu_br_en), .fu_issue_opcode(fu_br_opcode), .fu_issue_operand1(fu_br_op1), 
        .fu_issue_operand2(fu_br_op2), .fu_issue_pc(fu_br_pc), .fu_issue_imm(fu_br_imm), 
        .fu_issue_rob_idx(fu_br_tag), 
        .branch_cdb_valid(branch_cdb_v), .branch_cdb_tag(branch_cdb_t), .branch_cdb_val(branch_cdb_d), 
        .busy(f_br_busy)
    );
    
    logic [9:0] rob_flush_branch_pc;
    
    rob u_rob (
        .clk(clock), .reset(reset),
        .pipeline_flush_i(pipeline_flush),
        .rob_allocate_valid_i(rob_alloc_valid),
        .rob_allocate_data_i(rob_alloc_metadata),
        .wb_valid_i(cdb_valid),
        .wb_rob_tag_i(cdb_tag),
        .wb_result_val_i(cdb_val),
        .wb_branch_mispredict_i(branch_won_cdb && buffered_mispredict), 
        .commit_ready_i(commit_retire_en),
        .rob_full_o(rob_full),
        .rob_next_idx_o(rob_next_idx),
        .commit_valid_o(commit_valid),
        .commit_data_o(commit_data),
        .head_ptr_o(rob_head_tag),
        .flush_o(pipeline_flush),
        .flush_pc_o(redirect_pc),
        .flush_branch_pc_o(rob_flush_branch_pc) 
    );

    commit_stage u_commit (
        .clock(clock), .reset(reset),
        .rob_head_entry_i(commit_data), .rob_empty_i(!commit_valid), .lsq_ready_to_commit_i(1'b1),
        .reg_write_en_o(rf_wen), .reg_write_addr_o(rf_waddr), .reg_write_data_o(rf_wdata),
        .commit_en_o(commit_retire_en)
    );
    
    register u_regfile (
        .clock(clock), .reset(reset), .read_en(1'b1), 
        .read_addr1(rf_raddr1), .read_addr2(rf_raddr2), .read_data1(rf_rdata1), .read_data2(rf_rdata2), 
        .write_enable(rf_wen), .write(rf_waddr), .write_data(rf_wdata)
    );

    memory u_memory (
        .clock(clock), .reset(reset), 
        .pc_en(instr_pc_req), .pc_addr(instr_mem_addr), .pc_instr_out(instr_mem_data), .pc_done(instr_mem_valid), 
        .data_en(data_mem_req), .data_rw(data_mem_rw), .data_addr(data_mem_addr), 
        .data_wdata(data_mem_wdata), .data_out(data_mem_rdata), .data_done(data_mem_valid)
    );

endmodule
