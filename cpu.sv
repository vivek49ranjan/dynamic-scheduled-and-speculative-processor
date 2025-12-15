module cpu (
    input  logic         clock,
    input  logic         reset,

    output logic [9:0]   Pcounter,
    output logic [9:0]   mem_Raddrs,
    output logic [9:0]   mem_Waddrs,
    output logic [31:0]  write_data,

    input  logic [31:0]  read1_data,
    input  logic [31:0]  read2_data,

    output logic [31:0]  alu_result,

    output logic         rf_read1_en,
    output logic         rf_read2_en,
    output logic         rf_write_en
);
    // Import Packages
    import config_pkg::*;
    import cpu_types_pkg::*;

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // Fetch & Decode
    logic [9:0]           if_id_pc;
    logic [31:0]          if_id_opcode;
    logic [31:0]          instruction_mem_data; 
    logic                 decode_valid;
    decoded_instruction_t decode_inst;

    // Rename
    logic                 rename_stall;
    logic                 dispatch_can_proceed;
    logic [4:0]           reg_read_addr1, reg_read_addr2;
    logic                 renamed_valid;
    renamed_instruction_t renamed_inst;
    
    // ROB & Commit
    logic [3:0]                    rob_next_idx;
    logic                          rob_full;
    logic                          rob_allocate_valid;
    rob_instruction_metadata_t     rob_allocate_data;
    logic                          commit_valid;
    rob_entry_t                    commit_data;
    
    // Shadow Pointer & Flush Signals
    logic [3:0]                    commit_rob_idx; 
    logic                          rob_flush_internal; 
    logic [31:0]                   rob_flush_pc_dummy; 
    
    logic                          pipeline_flush;
    logic [31:0]                   redirect_pc;
    logic                          is_exception;
    logic                          commit_en;
    logic                          lsq_commit_en;
    logic [4:0]                    rf_write_address;
    logic [31:0]                   rf_write_data_internal;

    // ROB Intermediates (Fix for Elaboration Error)
    logic [3:0]                    rob_alloc_idx_wire;
    logic                          wb_exception_wire;

    // Dispatch
    logic                          alu_rs_full, lsq_rs_full, branch_rs_full;
    logic [3:0]                    lsq_next_idx_dummy;
    logic                          to_alu_valid, to_lsu_valid, to_branch_valid;
    alu_dispatch_packet_t          to_alu_packet;
    lsu_dispatch_packet_t          to_lsu_packet;
    branch_dispatch_packet_t       to_branch_packet;

    // Execution Units & RS Signals
    rs_status_t       alu_rs_status_unpacked[7:0]; 
    rs_status_t [7:0] alu_rs_status_packed;

    logic [7:0]       alu_rs_issue_en;
    logic             alu_fu_issue_en;
    logic [7:0]       alu_fu_issue_opcode;
    logic [31:0]      alu_fu_issue_operand1, alu_fu_issue_operand2;
    logic [4:0]       alu_fu_issue_dest_reg;
    logic [3:0]       alu_fu_issue_rob_idx;
    logic             fu_add_sub_busy, fu_logical_busy, fu_shift_busy;
    logic             fu_rotate_busy, fu_inc_dec_busy, fu_abs_busy, fu_compare_busy;

    logic             branch_fu_issue_en;
    logic [7:0]       branch_fu_issue_opcode;
    logic [31:0]      branch_fu_issue_operand1, branch_fu_issue_operand2;
    logic [3:0]       branch_fu_issue_rob_idx;
    logic             branch_taken_result;
    logic [7:0]       branch_addr_result;
    logic             branch_fu_busy;

    // LSU
    logic             lsq_ready_to_commit, lsq_full, lsq_empty;
    logic             lsu_mem_read_en, lsu_mem_write_en;
    logic [31:0]      lsu_mem_address_out, lsu_mem_write_data_out;
    logic             lsu_reg_write_en;
    logic [31:0]      lsu_reg_write_data;

    // CDB
    logic [31:0] cdb_value;
    logic [3:0]  cdb_tag;
    logic        cdb_valid;
    logic        cdb_alu_valid;
    logic [31:0] cdb_alu_value;
    logic [3:0]  cdb_alu_tag;
    logic        cdb_branch_valid;

    // =========================================================================
    // 1. Array Packing Logic
    // =========================================================================
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            alu_rs_status_packed[i] = alu_rs_status_unpacked[i];
        end
    end

    // =========================================================================
    // 2. Intermediate Assignments (Fix for Elaboration)
    // =========================================================================
    // Extract struct member to a simple wire before passing to module
    assign rob_alloc_idx_wire = renamed_inst.rob_idx;
    // Assign literal to a wire before passing to module
    assign wb_exception_wire  = 1'b0;

    // =========================================================================
    // 3. Shadow ROB Head Pointer Logic
    // =========================================================================
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            commit_rob_idx <= 4'b0;
        end else if (pipeline_flush || rob_flush_internal) begin
            commit_rob_idx <= 4'b0;
        end else if (commit_valid && commit_en) begin
            commit_rob_idx <= commit_rob_idx + 1'b1;
        end
    end

    // =========================================================================
    // 4. Outputs & Interfaces
    // =========================================================================

    assign Pcounter = if_id_pc;
    assign rf_read1_en = 1'b1;
    assign rf_read2_en = 1'b1;
    assign mem_Raddrs = lsu_mem_address_out[9:0];
    assign mem_Waddrs = lsu_mem_address_out[9:0];
    assign write_data = lsu_mem_write_data_out;
    assign alu_result = cdb_value; 
    assign instruction_mem_data = 32'b0; 

    // =========================================================================
    // 5. Module Instantiations
    // =========================================================================

    i_f u_fetch (
        .clock(clock), .reset(reset), .stall(rename_stall),
        .branch_taken(pipeline_flush), .branch_target(redirect_pc[9:0]),
        .instruction_mem_data(instruction_mem_data),
        .if_id_pc(if_id_pc), .if_id_opcode(if_id_opcode)
    );

    always_comb begin
        decode_valid = (if_id_opcode != 32'b0) && !pipeline_flush;
        decode_inst = '0;
        decode_inst.opcode = if_id_opcode[7:0];
        decode_inst.operand1_reg = if_id_opcode[12:8];
        decode_inst.operand2_reg = if_id_opcode[17:13];
        decode_inst.result_reg = if_id_opcode[22:18];
        decode_inst.load_destination = if_id_opcode[22:18];
        decode_inst.store_source = if_id_opcode[22:18];
        
        if (if_id_opcode[7:5] == 3'b001) decode_inst.instr_type = INSTR_LOAD;
        else if (if_id_opcode[7:5] == 3'b010) decode_inst.instr_type = INSTR_STORE;
        else if (if_id_opcode[7:5] == 3'b111) decode_inst.instr_type = INSTR_BRANCH;
        else decode_inst.instr_type = INSTR_ALU;
    end

    rename_stage u_rename (
        .clk(clock), .reset(reset || pipeline_flush),
        .decode_valid_i(decode_valid), .decode_inst_i(decode_inst), .decode_pc_i(if_id_pc),
        .rob_next_idx_i(rob_next_idx), .commit_valid_i(commit_valid),
        .commit_instr_i(commit_data.inst_data),
        .commit_rob_idx_i(commit_rob_idx),
        .rename_stall_i(rename_stall), .dispatch_can_proceed_i(dispatch_can_proceed),
        .reg_read_data1_i(read1_data), .reg_read_data2_i(read2_data),
        .reg_read_addr1_o(reg_read_addr1), .reg_read_addr2_o(reg_read_addr2),
        .renamed_valid_o(renamed_valid), .renamed_inst_o(renamed_inst)
    );

    assign lsq_next_idx_dummy = 4'b0;

    dispatch_stage u_dispatch (
        .clk(clock), .reset(reset || pipeline_flush),
        .renamed_valid_i(renamed_valid), .renamed_inst_i(renamed_inst),
        .lsq_next_idx_i(lsq_next_idx_dummy),
        .rob_full_i(rob_full), .alu_rs_full_i(alu_rs_full),
        .lsq_rs_full_i(lsq_full), .branch_rs_full_i(branch_rs_full),
        .rename_stall_o(rename_stall), .dispatch_can_proceed_o(dispatch_can_proceed),
        .rob_allocate_valid_o(rob_allocate_valid), .rob_allocate_data_o(rob_allocate_data),
        .to_alu_valid_o(to_alu_valid), .to_alu_packet_o(to_alu_packet),
        .to_lsu_valid_o(to_lsu_valid), .to_lsu_packet_o(to_lsu_packet),
        .to_branch_valid_o(to_branch_valid), .to_branch_packet_o(to_branch_packet)
    );

    // =========================================================================
    // ROB INSTANTIATION (Using Intermediate Wires)
    // =========================================================================
    rob u_rob (
        .clk                    (clock),
        .reset                  (reset),
        .pipeline_flush_i       (pipeline_flush),
        
        .rob_allocate_valid_i   (rob_allocate_valid),
        .rob_allocate_data_i    (rob_allocate_data),
        .rob_allocate_rob_idx_i (rob_alloc_idx_wire), // Use Wire
        
        .wb_valid_i             (cdb_valid),
        .wb_rob_tag_i           (cdb_tag),
        .wb_result_val_i        (cdb_value),
        .wb_has_exception_i     (wb_exception_wire),  // Use Wire
        
        .commit_ready_i         (commit_en),
        
        .rob_full_o             (rob_full),
        .rob_next_idx_o         (rob_next_idx),
        .commit_valid_o         (commit_valid),
        .commit_data_o          (commit_data),
        
        .flush_o                (rob_flush_internal),
        .flush_pc_o             (rob_flush_pc_dummy)
    );

    commit_stage u_commit (
        .clock(clock), .reset(reset),
        .rob_head_entry_i(commit_data), .rob_empty_i(!commit_valid),
        .lsq_ready_to_commit_i(lsq_ready_to_commit),
        .reg_write_en_o(rf_write_en), .reg_write_addr_o(rf_write_address),
        .reg_write_data_o(rf_write_data_internal),
        .pipeline_flush_o(pipeline_flush), .redirect_pc_o(redirect_pc),
        .is_exception_o(is_exception), .commit_en_o(commit_en), .lsq_commit_en_o(lsq_commit_en)
    );

    reservation_station u_alu_rs (
        .clk(clock), .reset(reset || pipeline_flush),
        .rs_dispatch_valid(to_alu_valid), .rs_dispatch_data(to_alu_packet),
        .rs_allocated_idx(), .rs_full_out(alu_rs_full),
        .fu_issue_opcode(alu_fu_issue_opcode),
        .fu_issue_operand1(alu_fu_issue_operand1), .fu_issue_operand2(alu_fu_issue_operand2),
        .fu_issue_dest_reg(alu_fu_issue_dest_reg), .fu_issue_rob_idx(alu_fu_issue_rob_idx),
        .fu_issue_en(alu_fu_issue_en),
        .cdb_valid(cdb_valid), .cdb_rob_tag(cdb_tag), .cdb_value(cdb_value),
        .rs_status_out(alu_rs_status_unpacked), 
        .rs_issue_en_in(alu_rs_issue_en),
        .fu_add_sub_busy(fu_add_sub_busy), .fu_logical_busy(fu_logical_busy),
        .fu_shift_busy(fu_shift_busy), .fu_rotate_busy(fu_rotate_busy),
        .fu_inc_dec_busy(fu_inc_dec_busy), .fu_abs_busy(fu_abs_busy), .fu_compare_busy(fu_compare_busy)
    );

    issue_stage u_alu_issue (
        .clk(clock), .reset(reset || pipeline_flush),
        .alu_rs_status_i(alu_rs_status_packed), 
        .alu_rs_issue_en_o(alu_rs_issue_en)
    );

    alu_top u_alu_top (
        .clk(clock), .reset(reset || pipeline_flush),
        .fu_issue_opcode(alu_fu_issue_opcode),
        .fu_issue_operand1(alu_fu_issue_operand1), .fu_issue_operand2(alu_fu_issue_operand2),
        .fu_issue_dest_reg(alu_fu_issue_dest_reg), .fu_issue_rob_idx(alu_fu_issue_rob_idx),
        .fu_issue_en(alu_fu_issue_en),
        .cdb_result_value(cdb_alu_value), .cdb_result_rob_tag(cdb_alu_tag), .cdb_result_valid(cdb_alu_valid),
        .fu_add_sub_busy(fu_add_sub_busy), .fu_logical_busy(fu_logical_busy),
        .fu_shift_busy(fu_shift_busy), .fu_rotate_busy(fu_rotate_busy),
        .fu_inc_dec_busy(fu_inc_dec_busy), .fu_abs_busy(fu_abs_busy), .fu_compare_busy(fu_compare_busy)
    );

    branch_reservation_station u_branch_rs (
        .clk(clock), .reset(reset || pipeline_flush),
        .rs_dispatch_valid(to_branch_valid), .rs_dispatch_data(to_branch_packet),
        .rs_allocated_idx(), .rs_full_out(branch_rs_full),
        .fu_issue_en(branch_fu_issue_en), .fu_issue_opcode(branch_fu_issue_opcode),
        .fu_issue_operand1(branch_fu_issue_operand1), .fu_issue_operand2(branch_fu_issue_operand2),
        .fu_issue_rob_idx(branch_fu_issue_rob_idx),
        .cdb_valid(cdb_valid), .cdb_rob_tag(cdb_tag), .cdb_value(cdb_value),
        .fu_branch_busy(branch_fu_busy)
    );

    branch_unit u_branch_exec (
        .clock(clock), .reset(reset || pipeline_flush),
        .fu_issue_en(branch_fu_issue_en), .fu_issue_opcode(branch_fu_issue_opcode),
        .fu_issue_operand1(branch_fu_issue_operand1), .fu_issue_operand2(branch_fu_issue_operand2),
        .fu_issue_rob_idx(branch_fu_issue_rob_idx),
        .branch_taken(branch_taken_result), .branch_address(branch_addr_result),
        .busy(branch_fu_busy), .stop_stall()
    );
    assign cdb_branch_valid = branch_taken_result;

    load_store_unit u_lsu (
        .clock(clock), .reset(reset || pipeline_flush),
        .dispatch_to_ls_rs(to_lsu_valid), .dispatch_data_i(to_lsu_packet),
        .ls_enable(lsq_commit_en),
        .mem_read_data_in(32'b0),
        .mem_operation_complete(lsu_mem_read_en | lsu_mem_write_en),
        .mem_read_en(lsu_mem_read_en), .mem_write_en(lsu_mem_write_en),
        .mem_address_out(lsu_mem_address_out), .mem_write_data_out(lsu_mem_write_data_out),
        .reg_write_en(lsu_reg_write_en), .reg_write_addr(), .reg_write_data(lsu_reg_write_data),
        .lsq_full(lsq_full), .lsq_empty(lsq_empty), .lsq_ready_to_commit(lsq_ready_to_commit)
    );

    // CDB Arbiter
    always_comb begin
        if (cdb_alu_valid) begin
            cdb_valid = 1'b1;
            cdb_value = cdb_alu_value;
            cdb_tag   = cdb_alu_tag;
        end else if (lsu_reg_write_en) begin
            cdb_valid = 1'b1;
            cdb_value = lsu_reg_write_data;
            cdb_tag   = commit_rob_idx; // Using Shadow Signal
        end else if (branch_taken_result) begin
            cdb_valid = 1'b1;
            cdb_value = {24'b0, branch_addr_result};
            cdb_tag   = branch_fu_issue_rob_idx;
        end else begin
            cdb_valid = 1'b0;
            cdb_value = 32'b0;
            cdb_tag   = 4'b0;
        end
    end
endmodule