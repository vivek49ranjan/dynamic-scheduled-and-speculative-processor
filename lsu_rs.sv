import config_pkg::*;
import cpu_types_pkg::*;

module lsu_reservation_station #(
    parameter LSQ_DEPTH = 8
)(
    input  logic                 clock, reset,
    
    input  logic                 rs_dispatch_valid,
    input  lsu_dispatch_packet_t rs_dispatch_data,
    output logic                 rs_full_out,

    input  logic                 cdb_valid_i,
    input  logic [4:0]           cdb_rob_tag_i,
    input  logic [31:0]          cdb_value_i,

    output logic                 fu_issue_valid,
    output logic                 fu_issue_is_load,
    output logic [9:0]           fu_issue_addr,
    output logic [31:0]          fu_issue_data,
    output logic [4:0]           fu_issue_rob_tag,
    output logic                 fu_issue_fwd_valid,
    output logic [31:0]          fu_issue_fwd_data,
    
    output logic                 fu_commit_store_valid,
    output logic [9:0]           fu_commit_store_addr,
    output logic [31:0]          fu_commit_store_data,
    
    input  logic                 fu_busy_i,
    input  logic [4:0]           fu_active_rob_tag_i,
    
    input  logic                 commit_store_req_i,
    input  logic                 lsq_store_done_i
);

    lsq_entry_t lsq [0:LSQ_DEPTH-1];
    logic [2:0] head, tail;
    logic [3:0] count;

    assign rs_full_out = (count >= 4'd7);

    logic addr_ready_comb;
    logic [9:0] addr_val_comb;
    logic data_ready_comb;
    logic [31:0] data_val_comb;

    always_comb begin
        addr_ready_comb = rs_dispatch_data.addr_op_is_ready;
        addr_val_comb   = rs_dispatch_data.addr_op_val[9:0];
        if (!addr_ready_comb && cdb_valid_i && (rs_dispatch_data.addr_op_rob_tag == cdb_rob_tag_i)) begin
            addr_ready_comb = 1'b1;
            addr_val_comb   = cdb_value_i[9:0];
        end

        data_ready_comb = rs_dispatch_data.data_op_is_ready;
        data_val_comb   = rs_dispatch_data.data_op_val;
        if (!data_ready_comb && cdb_valid_i && (rs_dispatch_data.data_op_rob_tag == cdb_rob_tag_i)) begin
            data_ready_comb = 1'b1;
            data_val_comb   = cdb_value_i;
        end
    end

    logic issue_found;
    logic [2:0] issue_idx;
    logic do_forwarding;
    logic [31:0] forwarded_data;
    
    always_comb begin
        issue_found    = 1'b0;
        issue_idx      = 3'd0;
        do_forwarding  = 1'b0;
        forwarded_data = 32'd0;

        for (int i = 0; i < LSQ_DEPTH; i++) begin
            logic [2:0] c_idx;
            c_idx = head + i[2:0]; 

            if (!issue_found && (i < count) && lsq[c_idx].busy && !lsq[c_idx].executed) begin
                if (!lsq[c_idx].is_load) begin
                    if (lsq[c_idx].addr_ready && lsq[c_idx].data_ready) begin
                        issue_found = 1'b1;
                        issue_idx   = c_idx;
                    end
                end 
                else if (lsq[c_idx].addr_ready) begin
                    logic conflict;
                    logic fwd_hit;
                    logic [31:0] temp_fwd;
                    
                    conflict = 1'b0;
                    fwd_hit  = 1'b0;
                    temp_fwd = 32'd0;

                    for (int j = 0; j < LSQ_DEPTH; j++) begin
                        logic [2:0] o_idx;
                        o_idx = head + j[2:0];
                        
                        if (j < i) begin 
                            if (!lsq[o_idx].is_load && lsq[o_idx].busy) begin
                                if (!lsq[o_idx].addr_ready) begin
                                    conflict = 1'b1; 
                                end else if (lsq[o_idx].addr == lsq[c_idx].addr) begin
                                    if (lsq[o_idx].data_ready) begin
                                        fwd_hit  = 1'b1;
                                        temp_fwd = lsq[o_idx].data;
                                        conflict = 1'b0; 
                                    end else begin
                                        conflict = 1'b1; 
                                    end
                                end
                            end
                        end
                    end

                    if (!conflict) begin
                        issue_found = 1'b1;
                        issue_idx   = c_idx;
                        if (fwd_hit) begin
                            do_forwarding  = 1'b1;
                            forwarded_data = temp_fwd;
                        end
                    end
                end
            end
        end
    end

    logic do_enqueue, do_retire;
    assign do_enqueue = rs_dispatch_valid && !rs_full_out;
    
    assign do_retire  = lsq[head].busy && lsq[head].executed && 
                        (lsq[head].is_load ? (!fu_busy_i || (lsq[head].rob_tag != fu_active_rob_tag_i)) 
                                           : lsq_store_done_i);

    logic actually_issue;
    assign actually_issue = !fu_busy_i && issue_found && !(fu_commit_store_valid);

    assign fu_issue_valid     = actually_issue;
    assign fu_issue_is_load   = lsq[issue_idx].is_load;
    assign fu_issue_addr      = lsq[issue_idx].addr;
    assign fu_issue_data      = lsq[issue_idx].data;
    assign fu_issue_rob_tag   = lsq[issue_idx].rob_tag;
    assign fu_issue_fwd_valid = do_forwarding;
    assign fu_issue_fwd_data  = forwarded_data;

    assign fu_commit_store_valid = commit_store_req_i && lsq[head].busy && !lsq[head].is_load && lsq[head].executed && !lsq_store_done_i;   
	 assign fu_commit_store_addr  = lsq[head].addr;
    assign fu_commit_store_data  = lsq[head].data;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            head <= 3'd0; tail <= 3'd0; count <= 4'd0;
            for (int k = 0; k < LSQ_DEPTH; k++) lsq[k].busy <= 1'b0;
        end else begin
            if (cdb_valid_i) begin
                for (int k = 0; k < LSQ_DEPTH; k++) begin
                    if (lsq[k].busy && !lsq[k].executed) begin
                        if (!lsq[k].addr_ready && (lsq[k].addr_tag == cdb_rob_tag_i)) begin
                            lsq[k].addr_ready <= 1'b1;
                            lsq[k].addr       <= cdb_value_i[9:0] + lsq[k].imm; 
                        end
                        if (!lsq[k].data_ready && (lsq[k].data_tag == cdb_rob_tag_i)) begin
                            lsq[k].data_ready <= 1'b1;
                            lsq[k].data       <= cdb_value_i;
                        end
                    end
                end
            end

            if (do_enqueue) begin 
                lsq[tail].busy      <= 1'b1;
                lsq[tail].executed   <= 1'b0;
                lsq[tail].is_load    <= (rs_dispatch_data.opcode == OPCODE_LOAD);
                lsq[tail].rob_tag    <= rs_dispatch_data.rob_idx;
                lsq[tail].imm        <= rs_dispatch_data.immediate[9:0];
                
                lsq[tail].addr_ready <= addr_ready_comb;
                lsq[tail].addr_tag   <= rs_dispatch_data.addr_op_rob_tag;
                lsq[tail].addr       <= addr_val_comb + rs_dispatch_data.immediate[9:0];
                
                lsq[tail].data_ready <= (rs_dispatch_data.opcode == OPCODE_LOAD) ? 1'b1 : data_ready_comb;
                lsq[tail].data_tag   <= rs_dispatch_data.data_op_rob_tag;
                lsq[tail].data       <= data_val_comb;
                
                tail <= tail + 3'd1;
            end

            if (do_retire) begin
                lsq[head].busy <= 1'b0;
                head <= head + 3'd1;
            end

            case ({do_enqueue, do_retire})
                2'b10: count <= count + 4'd1;
                2'b01: count <= count - 4'd1;
                default: ;
            endcase

            if (actually_issue) begin
                lsq[issue_idx].executed <= 1'b1;
            end
        end
    end
endmodule
