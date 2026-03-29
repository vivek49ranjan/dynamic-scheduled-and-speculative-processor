import config_pkg::*;
import cpu_types_pkg::*;

module load_store_unit #(
    parameter LSQ_DEPTH = 8
)(
    input  logic             clock, reset,
    
    input  logic             lsu_dispatch_valid,
    input  lsu_dispatch_packet_t lsu_packet_i,
    output logic             rs_full_o,

    input  logic             cdb_valid_i,
    input  logic [4:0]       cdb_rob_tag_i,
    input  logic [31:0]      cdb_value_i,

    output logic [9:0]       data_mem_addr,
    output logic [31:0]      data_mem_write_data,
    output logic             data_mem_read_write, 
    output logic             data_mem_req,
    input  logic             data_mem_valid,      
    input  logic [31:0]      data_mem_data_i,     
    
    output logic [31:0]      lsu_cdb_value,
    output logic [4:0]       lsu_cdb_rob_tag,     
    output logic             lsu_cdb_valid
);

    typedef struct packed {
        logic        valid;
        logic        executed;
        logic        is_load;
        logic        addr_ready;
        logic [9:0]  addr; 
        logic [4:0]  addr_tag;  
        logic [9:0]  imm;  
        logic        data_ready;
        logic [31:0] data; 
        logic [4:0]  data_tag;  
        logic [4:0]  rob_tag;
    } lsq_entry_t;

    lsq_entry_t lsq [0:LSQ_DEPTH-1];
    logic [2:0] head, tail;
    logic [3:0] count;

    logic mem_busy;
    logic [4:0] mem_active_rob_tag;

    assign rs_full_o = (count >= 4'd8);

    logic addr_ready_comb;
    logic [9:0] addr_val_comb;
    logic data_ready_comb;
    logic [31:0] data_val_comb;

    always_comb begin
        addr_ready_comb = lsu_packet_i.addr_op_is_ready;
        addr_val_comb   = lsu_packet_i.addr_op_val[9:0];
        if (!addr_ready_comb && cdb_valid_i && (lsu_packet_i.addr_op_rob_tag == cdb_rob_tag_i)) begin
            addr_ready_comb = 1'b1;
            addr_val_comb   = cdb_value_i[9:0];
        end

        data_ready_comb = lsu_packet_i.data_op_is_ready;
        data_val_comb   = lsu_packet_i.data_op_val;
        if (!data_ready_comb && cdb_valid_i && (lsu_packet_i.data_op_rob_tag == cdb_rob_tag_i)) begin
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

            if (!issue_found && (i < count) && lsq[c_idx].valid && !lsq[c_idx].executed) begin
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
                            if (!lsq[o_idx].is_load && lsq[o_idx].valid) begin
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
    assign do_enqueue = lsu_dispatch_valid && !rs_full_o;
    assign do_retire  = lsq[head].valid && lsq[head].executed && 
                        (!mem_busy || (lsq[head].rob_tag != mem_active_rob_tag));

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            head <= 3'd0; tail <= 3'd0; count <= 4'd0;
            mem_busy <= 1'b0; data_mem_req <= 1'b0;
            lsu_cdb_valid <= 1'b0;
            for (int k = 0; k < LSQ_DEPTH; k++) lsq[k].valid <= 1'b0;
        end else begin
            lsu_cdb_valid <= 1'b0;
            data_mem_req  <= 1'b0;

            if (data_mem_valid && mem_busy) begin
                mem_busy <= 1'b0;
                lsu_cdb_valid   <= 1'b1;
                lsu_cdb_rob_tag <= mem_active_rob_tag;
                lsu_cdb_value   <= data_mem_data_i; 
            end

            if (cdb_valid_i) begin
                for (int k = 0; k < LSQ_DEPTH; k++) begin
                    if (lsq[k].valid && !lsq[k].executed) begin
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
                lsq[tail].valid      <= 1'b1;
                lsq[tail].executed   <= 1'b0;
                lsq[tail].is_load    <= (lsu_packet_i.opcode == OPCODE_LOAD);
                lsq[tail].rob_tag    <= lsu_packet_i.rob_idx;
                lsq[tail].imm        <= lsu_packet_i.immediate[9:0];
                
                lsq[tail].addr_ready <= addr_ready_comb;
                lsq[tail].addr_tag   <= lsu_packet_i.addr_op_rob_tag;
                lsq[tail].addr       <= addr_ready_comb ? (addr_val_comb + lsu_packet_i.immediate[9:0]) : addr_val_comb;
                
                lsq[tail].data_ready <= (lsu_packet_i.opcode == OPCODE_LOAD) ? 1'b1 : data_ready_comb;
                lsq[tail].data_tag   <= lsu_packet_i.data_op_rob_tag;
                lsq[tail].data       <= data_val_comb;
                
                tail <= tail + 3'd1;
            end

            if (do_retire) begin
                lsq[head].valid <= 1'b0;
                head <= head + 3'd1;
            end

            case ({do_enqueue, do_retire})
                2'b10: count <= count + 4'd1;
                2'b01: count <= count - 4'd1;
                default: ;
            endcase

            if (!mem_busy && issue_found) begin
                if (do_forwarding) begin
                    lsq[issue_idx].executed <= 1'b1;
                    lsu_cdb_valid   <= 1'b1;
                    lsu_cdb_rob_tag <= lsq[issue_idx].rob_tag;
                    lsu_cdb_value   <= forwarded_data; 
                end else begin
                    lsq[issue_idx].executed <= 1'b1;
                    mem_busy <= 1'b1;
                    mem_active_rob_tag  <= lsq[issue_idx].rob_tag;
                    data_mem_req        <= 1'b1; 
                    data_mem_addr       <= lsq[issue_idx].addr;
                   
                    data_mem_read_write <= lsq[issue_idx].is_load; 
                    data_mem_write_data <= lsq[issue_idx].data;
                end
            end 
        end
    end
endmodule
