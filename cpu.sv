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

    logic pipeline_flush, rob_full, rename_stall;
    logic dispatch_success; 
    logic dispatch_stall;
	logic [9:0] redirect_pc;
    logic [9:0]  id_pc;
    logic        id_valid, rob_alloc_valid, rob_fill_valid, commit_retire_en, commit_valid;
    logic [4:0]  rob_alloc_idx, rob_fill_idx, rob_head_tag;
    
    logic [52:0] iq_in_packet, iq_out_packet;
    logic        iq_enq_v, iq_deq_v, iq_full;

    logic        cdb_valid;
    logic [4:0]  cdb_tag;
    logic [31:0] cdb_val;
    logic        alu_cdb_v, lsu_cdb_v, branch_cdb_v;
    logic [4:0]  alu_cdb_t, lsu_cdb_t, branch_cdb_t;
    logic [31:0] alu_cdb_d, lsu_cdb_d, branch_cdb_d;
    logic        branch_cdb_mispredict; 

    rs_status_t [7:0] alu_rs_status_packed;
    rs_status_t       alu_rs_status_unpacked [7:0];
    logic [7:0]       alu_issue_en_bus;
    
    logic [7:0]  fu_alu_opcode, fu_br_opcode;
    logic [31:0] fu_alu_op1, fu_alu_op2, fu_br_op1, fu_br_op2, fu_br_pc;
    logic [7:0]  fu_br_imm;
    logic [4:0]  fu_alu_rd, fu_alu_tag, fu_br_tag;
    logic        fu_alu_en, fu_br_en;
    logic        f_add_b, f_log_b, f_shf_b, f_rot_b, f_inc_b, f_abs_b, f_cmp_b, f_br_busy;

    logic        fu_br_pred_taken;
    logic [9:0]  fu_br_pred_target;

    logic [9:0]  instr_mem_addr, data_mem_addr;
    logic [31:0] instr_mem_data, data_mem_wdata, data_mem_rdata;
    logic        instr_mem_valid, data_mem_valid, instr_pc_req, data_mem_req, data_mem_rw, rf_wen;
    logic [4:0]  rf_raddr1, rf_raddr2, rf_waddr;
    logic [31:0] rf_rdata1, rf_rdata2, rf_wdata;

    logic alu_rs_full, branch_rs_full, lsq_rs_full, to_alu_v, to_lsu_v, to_br_v;
    alu_dispatch_packet_t    to_alu_packet;
    lsu_dispatch_packet_t    to_lsu_packet;
    branch_dispatch_packet_t to_branch_packet;
    
    decoded_instruction_t      decode_inst;
    logic                      rn_valid;
    renamed_instruction_t      rn_inst;
    rob_instruction_metadata_t rob_fill_data;
    rob_entry_t                commit_data;

    logic        bp_train_en;
    logic [9:0]  bp_train_pc;
    logic        bp_train_taken;
    logic [9:0]  bp_train_target;
    logic        branch_won_cdb;

    typedef struct packed {
        logic [4:0]  tag;
        logic [31:0] val;
        logic        is_branch;
        logic        mispredict;
    } cdb_packet_t;

    cdb_packet_t cdb_fifo [0:63];
    logic [5:0] cdb_head, cdb_tail;
    logic [6:0] cdb_count;
    logic [1:0] push_amt;
    
    logic [5:0] tail_idx_1, tail_idx_2, tail_idx_3;

    assign push_amt = {1'b0, alu_cdb_v} + {1'b0, lsu_cdb_v} + {1'b0, branch_cdb_v};

    assign tail_idx_1 = cdb_tail;
    assign tail_idx_2 = (cdb_tail + {5'b0, alu_cdb_v}) & 6'd63;
    assign tail_idx_3 = (cdb_tail + {5'b0, alu_cdb_v} + {5'b0, lsu_cdb_v}) & 6'd63;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            cdb_head <= 6'd0;
            cdb_tail <= 6'd0;
            cdb_count <= 7'd0;
            for (int i=0; i<64; i++) cdb_fifo[i] <= '0;
        end else if (pipeline_flush) begin
            cdb_head <= 6'd0;
            cdb_tail <= 6'd0;
            cdb_count <= 7'd0;
            for (int i=0; i<64; i++) cdb_fifo[i] <= '0;
        end else begin
            if (cdb_count > 0) begin
                cdb_head <= (cdb_head + 6'd1) & 6'd63;
                cdb_count <= cdb_count - 7'd1 + {5'b0, push_amt};
            end else begin
                cdb_count <= cdb_count + {5'b0, push_amt};
            end
            
            cdb_tail <= (cdb_tail + {4'b0, push_amt}) & 6'd63;

            if (alu_cdb_v) begin
                cdb_fifo[tail_idx_1].tag <= alu_cdb_t;
                cdb_fifo[tail_idx_1].val <= alu_cdb_d;
                cdb_fifo[tail_idx_1].is_branch <= 1'b0;
                cdb_fifo[tail_idx_1].mispredict <= 1'b0;
            end
            if (lsu_cdb_v) begin
                cdb_fifo[tail_idx_2].tag <= lsu_cdb_t;
                cdb_fifo[tail_idx_2].val <= lsu_cdb_d;
                cdb_fifo[tail_idx_2].is_branch <= 1'b0;
                cdb_fifo[tail_idx_2].mispredict <= 1'b0;
            end
            if (branch_cdb_v) begin
                cdb_fifo[tail_idx_3].tag <= branch_cdb_t;
                cdb_fifo[tail_idx_3].val <= branch_cdb_d;
                cdb_fifo[tail_idx_3].is_branch <= 1'b1;
                cdb_fifo[tail_idx_3].mispredict <= branch_cdb_mispredict; // UPDATED
            end
        end
    end
    assign cdb_valid = (cdb_count > 0);
    assign cdb_tag   = cdb_fifo[cdb_head].tag;
    assign cdb_val   = cdb_fifo[cdb_head].val;
    assign branch_won_cdb = (cdb_count > 0) && cdb_fifo[cdb_head].is_branch;
    
    logic buffered_mispredict;
    assign buffered_mispredict = (cdb_count > 0) && cdb_fifo[cdb_head].mispredict;

    logic is_bogus_branch;

    always_comb begin
        is_bogus_branch = commit_data.inst_data.pred_taken && 
                          (commit_data.inst_data.instr_type != INSTR_BRANCH);
        bp_train_en = commit_valid && commit_retire_en && 
                      ((commit_data.inst_data.instr_type == INSTR_BRANCH) || is_bogus_branch);
        bp_train_pc = commit_data.inst_data.pc[9:0];

        if (is_bogus_branch) begin
            bp_train_taken  = 1'b0;
            bp_train_target = commit_data.inst_data.pc[9:0] + 10'd1; 
        end else begin
            bp_train_target = redirect_pc[9:0];
            bp_train_taken  = (redirect_pc[9:0] != (commit_data.inst_data.pc[9:0] + 10'd1));
        end
    end
    assign current_pc_out = id_pc;
    assign alu_result     = (commit_valid) ? commit_data.result_value : 32'b0;

    i_f u_fetch (
        .clock(clock), .reset(reset), 
        .stall(1'b0),
        .flush_en(pipeline_flush), 
        .flush_target(redirect_pc[9:0]), 
        .bp_train_en(bp_train_en), .bp_train_pc(bp_train_pc),
        .bp_train_taken(bp_train_taken), .bp_train_target(bp_train_target),
        .instruction_mem_data(instr_mem_data), 
        .instruction_valid(instr_mem_valid), 
        .queue_full(iq_full), .enqueue_valid(iq_enq_v),
        .fetch_packet_o(iq_in_packet),  // UPDATED: Now includes predictions natively
        .start_fetch(instr_pc_req), .pc_to_reader(instr_mem_addr), 
        .ext_pc_set(ext_pc_set), .ext_pc_val(ext_pc_val)
    );

    instruction_queue u_iq (
        .clk(clock), 
        .reset(reset), 
        .flush(pipeline_flush),
        .enqueue_valid(iq_enq_v), .enqueue_data(iq_in_packet),
        .dequeue_valid(iq_deq_v), .dequeue_data(iq_out_packet),
        .dequeue_request(iq_deq_v && !rename_stall && !pipeline_flush), 
        .queue_full(iq_full)
    );

    assign dispatch_success = id_valid && !rename_stall && !pipeline_flush;

    decode u_decode (
        .clock(clock), .reset(reset), 
        .if_id_valid(iq_deq_v), 
        .if_id_pred_taken(iq_out_packet[52]),       
        .if_id_pred_target(iq_out_packet[51:42]),   
        .if_id_pc(iq_out_packet[41:32]), 
        .if_id_opcode(iq_out_packet[31:0]), 
        .stall(rename_stall), .flush(pipeline_flush), 
        .id_valid(id_valid), .id_pc(id_pc), 
        .decoded_instruction(decode_inst)
    );
    
    rename_stage u_rename (
        .clk(clock), .reset(reset), .flush_i(pipeline_flush), 
        .id_valid_i(id_valid), .decode_inst_i(decode_inst), .decode_pc_i(id_pc), 
        .rob_alloc_idx_i(rob_alloc_idx),
        .rob_full_i(rob_full),
        .rob_alloc_valid_o(rob_alloc_valid),
        .commit_valid_i(commit_retire_en), .commit_instr_i(commit_data.inst_data), .commit_rob_idx_i(rob_head_tag), 
        .dispatch_stall_i(dispatch_stall),
        .rn_valid_o(rn_valid), .rn_inst_o(rn_inst), .rename_stall_o(rename_stall)
    );
    
    logic [4:0]  d_r_idx1, d_r_idx2;
    logic        d_r_rdy1, d_r_rdy2;
    logic        d_r_bsy1, d_r_bsy2;
    logic [31:0] d_r_val1, d_r_val2;

    dispatch_stage u_dispatch (
        .clk(clock), .reset(reset), .flush_i(pipeline_flush), 
        .rn_valid_i(rn_valid), .rn_inst_i(rn_inst), 
        .dispatch_stall_o(dispatch_stall),
        .rf_raddr1_o(rf_raddr1), .rf_raddr2_o(rf_raddr2), .rf_rdata1_i(rf_rdata1), .rf_rdata2_i(rf_rdata2), 
        .commit_wen_i(rf_wen), .commit_waddr_i(rf_waddr), .commit_wdata_i(rf_wdata), 
        .cdb_valid_i(cdb_valid), .cdb_tag_i(cdb_tag), .cdb_val_i(cdb_val),
        .rob_read_idx1_o(d_r_idx1), .rob_read_ready1_i(d_r_rdy1), .rob_read_busy1_i(d_r_bsy1), .rob_read_val1_i(d_r_val1),
        .rob_read_idx2_o(d_r_idx2), .rob_read_ready2_i(d_r_rdy2), .rob_read_busy2_i(d_r_bsy2), .rob_read_val2_i(d_r_val2),
        .alu_rs_full_i(alu_rs_full), .lsq_rs_full_i(lsq_rs_full), .branch_rs_full_i(branch_rs_full), 
        .rob_fill_valid_o(rob_fill_valid), .rob_fill_idx_o(rob_fill_idx), .rob_fill_data_o(rob_fill_data),
        .to_alu_valid_o(to_alu_v), .to_alu_packet_o(to_alu_packet), 
        .to_lsu_valid_o(to_lsu_v), .to_lsu_packet_o(to_lsu_packet), 
        .to_branch_valid_o(to_br_v), .to_branch_packet_o(to_branch_packet)
    );

    issue_stage u_issue (
        .clk(clock), .reset(reset), .alu_rs_status_i(alu_rs_status_packed), .alu_rs_issue_en_o(alu_issue_en_bus)
    );
    
    reservation_station u_alu_rs (
        .clk(clock), .reset(reset | pipeline_flush), 
        .rs_dispatch_valid(to_alu_v), .rs_dispatch_data(to_alu_packet), .rs_full_out(alu_rs_full), 
        .cdb_valid(cdb_valid), .cdb_rob_tag(cdb_tag), .cdb_value(cdb_val), 
        .fu_issue_opcode(fu_alu_opcode), .fu_issue_operand1(fu_alu_op1), .fu_issue_operand2(fu_alu_op2), 
        .fu_issue_dest_reg(fu_alu_rd), .fu_issue_rob_idx(fu_alu_tag), .fu_issue_en(fu_alu_en), 
        .rs_status_out(alu_rs_status_unpacked), .rs_issue_en_in(alu_issue_en_bus), 
        .fu_add_sub_busy(f_add_b), .fu_logical_busy(f_log_b), .fu_shift_busy(f_shf_b), 
        .fu_compare_busy(f_cmp_b)
    );
    
    alu_top u_alu_top (
        .clk(clock), .reset(reset | pipeline_flush), 
        .fu_issue_opcode(fu_alu_opcode), .fu_issue_operand1(fu_alu_op1), .fu_issue_operand2(fu_alu_op2), 
        .fu_issue_dest_reg(fu_alu_rd), .fu_issue_rob_idx(fu_alu_tag), .fu_issue_en(fu_alu_en), 
        .cdb_result_value(alu_cdb_d), .cdb_result_rob_tag(alu_cdb_t), .cdb_result_valid(alu_cdb_v),
        .cdb_dest_reg(), 
        .fu_add_sub_busy(f_add_b), .fu_logical_busy(f_log_b), .fu_shift_busy(f_shf_b), .fu_compare_busy(f_cmp_b)
    );
	 logic commit_store_req;
    logic lsq_store_done;   
    
    logic        lsu_fu_issue_valid;
    logic        lsu_fu_issue_is_load;
    logic [9:0]  lsu_fu_issue_addr;
    logic [31:0] lsu_fu_issue_data;
    logic [4:0]  lsu_fu_issue_rob_tag;
    logic        lsu_fu_issue_fwd_valid;
    logic [31:0] lsu_fu_issue_fwd_data;
    logic        lsu_fu_commit_store_valid;
    logic [9:0]  lsu_fu_commit_store_addr;
    logic [31:0] lsu_fu_commit_store_data;
    logic        lsu_fu_busy;
    logic [4:0]  lsu_fu_active_rob_tag;

    lsu_reservation_station u_lsu_rs (
        .clock(clock), .reset(reset | pipeline_flush), 
        
        .rs_dispatch_valid(to_lsu_v), .rs_dispatch_data(to_lsu_packet), 
        .rs_full_out(lsq_rs_full),

        .cdb_valid_i(cdb_valid), .cdb_rob_tag_i(cdb_tag), .cdb_value_i(cdb_val),

        .fu_issue_valid(lsu_fu_issue_valid),
        .fu_issue_is_load(lsu_fu_issue_is_load),
        .fu_issue_addr(lsu_fu_issue_addr),
        .fu_issue_data(lsu_fu_issue_data),
        .fu_issue_rob_tag(lsu_fu_issue_rob_tag),
        .fu_issue_fwd_valid(lsu_fu_issue_fwd_valid),
        .fu_issue_fwd_data(lsu_fu_issue_fwd_data),
        
        .fu_commit_store_valid(lsu_fu_commit_store_valid),
        .fu_commit_store_addr(lsu_fu_commit_store_addr),
        .fu_commit_store_data(lsu_fu_commit_store_data),
        
        .fu_busy_i(lsu_fu_busy),
        .fu_active_rob_tag_i(lsu_fu_active_rob_tag),
        
        .commit_store_req_i(commit_store_req),
        .lsq_store_done_i(lsq_store_done)
    );
    
    lsu_functional_unit u_lsu_fu (
        .clock(clock), .reset(reset | pipeline_flush), 
        
        .fu_issue_valid(lsu_fu_issue_valid),
        .fu_issue_is_load(lsu_fu_issue_is_load),
        .fu_issue_addr(lsu_fu_issue_addr),
        .fu_issue_data(lsu_fu_issue_data),
        .fu_issue_rob_tag(lsu_fu_issue_rob_tag),
        .fu_issue_fwd_valid(lsu_fu_issue_fwd_valid),
        .fu_issue_fwd_data(lsu_fu_issue_fwd_data),
        
        .fu_commit_store_valid(lsu_fu_commit_store_valid),
        .fu_commit_store_addr(lsu_fu_commit_store_addr),
        .fu_commit_store_data(lsu_fu_commit_store_data),
        
        .fu_busy_o(lsu_fu_busy),
        .fu_active_rob_tag_o(lsu_fu_active_rob_tag),
        
        .data_mem_addr(data_mem_addr), .data_mem_write_data(data_mem_wdata), 
        .data_mem_read_write(data_mem_rw), .data_mem_req(data_mem_req), 
        .data_mem_data_i(data_mem_rdata), .data_mem_valid(data_mem_valid), 
        
        .lsu_cdb_valid(lsu_cdb_v), .lsu_cdb_rob_tag(lsu_cdb_t), .lsu_cdb_value(lsu_cdb_d), 
        
        .lsq_store_done_o(lsq_store_done)
    );
    
    branch_reservation_station u_br_rs (
        .clock(clock), .reset(reset | pipeline_flush), 
        .rs_dispatch_valid(to_br_v), .rs_dispatch_data(to_branch_packet), .rs_full_out(branch_rs_full), 
        .fu_issue_en(fu_br_en), .fu_issue_opcode(fu_br_opcode), .fu_issue_operand1(fu_br_op1), 
        .fu_issue_operand2(fu_br_op2), .fu_issue_rob_idx(fu_br_tag), .fu_issue_pc(fu_br_pc), .fu_issue_imm(fu_br_imm), 
        .fu_issue_pred_taken(fu_br_pred_taken),   
        .fu_issue_pred_target(fu_br_pred_target), 
        .cdb_valid(cdb_valid), .cdb_rob_tag(cdb_tag), .cdb_value(cdb_val)
    );
    
    branch_unit u_br_fu (
        .clock(clock), .reset(reset | pipeline_flush), 
        .fu_issue_en(fu_br_en), .fu_issue_opcode(fu_br_opcode), .fu_issue_operand1(fu_br_op1), 
        .fu_issue_operand2(fu_br_op2), .fu_issue_pc(fu_br_pc), .fu_issue_imm(fu_br_imm), 
        .fu_issue_rob_idx(fu_br_tag), 
        .fu_issue_pred_taken(fu_br_pred_taken),   
        .fu_issue_pred_target(fu_br_pred_target),
        .branch_cdb_valid(branch_cdb_v), .branch_cdb_tag(branch_cdb_t), .branch_cdb_val(branch_cdb_d), 
        .branch_cdb_mispredict(branch_cdb_mispredict) 
    );
    
    logic [9:0] rob_flush_branch_pc;
    
    rob u_rob (
        .clk(clock), .reset(reset),
        .pipeline_flush_i(pipeline_flush),
        .rob_alloc_valid_i(rob_alloc_valid),
        .rob_full_o(rob_full),
        .rob_alloc_idx_o(rob_alloc_idx),
        .rob_fill_valid_i(rob_fill_valid),
        .rob_fill_idx_i(rob_fill_idx),
        .rob_fill_data_i(rob_fill_data),
        .cdb_valid_i(cdb_valid),
        .cdb_rob_tag_i(cdb_tag),
        .cdb_result_val_i(cdb_val),
        .cdb_branch_mispredict_i(branch_won_cdb && buffered_mispredict), 
        .commit_ready_i(commit_retire_en),
        .commit_valid_o(commit_valid),
        .commit_data_o(commit_data),
        .head_ptr_o(rob_head_tag),
        .flush_o(pipeline_flush),
        .flush_pc_o(redirect_pc),
        .flush_branch_pc_o(rob_flush_branch_pc),
        .read_idx1_i(d_r_idx1), .read_ready1_o(d_r_rdy1), .read_busy1_o(d_r_bsy1), .read_val1_o(d_r_val1),
        .read_idx2_i(d_r_idx2), .read_ready2_o(d_r_rdy2), .read_busy2_o(d_r_bsy2), .read_val2_o(d_r_val2)
    );

    commit_stage u_commit (
        .clock(clock), .reset(reset),
        .rob_head_entry_i(commit_data), .commit_valid_i(commit_valid), .lsq_ready_to_commit_i(lsq_store_done),
        .commit_store_req_o(commit_store_req),
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
