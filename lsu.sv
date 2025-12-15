module load_store_unit (
    input  clock,
    input  reset,
    input  logic                   dispatch_to_ls_rs,
    input  lsu_dispatch_packet_t   dispatch_data_i,
    input  logic                   ls_enable,
    input  logic [31:0]            mem_read_data_in,
    input  logic                   mem_operation_complete,
    output logic                   mem_read_en,
    output logic                   mem_write_en,
    output logic [31:0]            mem_address_out,
    output logic [31:0]            mem_write_data_out,
    output logic                   reg_write_en,
    output logic [4:0]             reg_write_addr,
    output logic [31:0]            reg_write_data,
    output logic                   lsq_full,
    output logic                   lsq_empty,
    output logic                   lsq_ready_to_commit
);
    import cpu_types_pkg::*;
    parameter LSQ_DEPTH = 8;

    load_store_queue #(.LSQ_DEPTH(LSQ_DEPTH)) u_lsq (
        .clock(clock),
        .reset(reset),
        .dispatch_to_ls_rs(dispatch_to_ls_rs),
        .enqueue_data(dispatch_data_i),
        .ls_enable(ls_enable),
        .mem_read_data_in(mem_read_data_in),
        .mem_operation_complete_i(mem_operation_complete),
        .mem_read_en(mem_read_en),
        .mem_address_out(mem_address_out),
        .mem_write_data_out(mem_write_data_out),
        .mem_write_en(mem_write_en),
        .reg_write_en(reg_write_en),
        .reg_write_addr(reg_write_addr),
        .reg_write_data(reg_write_data),
        .lsq_full(lsq_full),
        .lsq_empty(lsq_empty),
        .lsq_ready_to_commit(lsq_ready_to_commit)
    );
endmodule

module load_store_queue (
    input  clock,
    input  reset,
    input  logic                   dispatch_to_ls_rs,
    input  lsu_dispatch_packet_t   enqueue_data,
    input  logic                   ls_enable,
    input  logic [31:0]            mem_read_data_in,
    input  logic                   mem_operation_complete_i,
    output logic                   mem_read_en,
    output logic [31:0]            mem_address_out,
    output logic [31:0]            mem_write_data_out,
    output logic                   mem_write_en,
    output logic                   reg_write_en,
    output logic [4:0]             reg_write_addr,
    output logic [31:0]            reg_write_data,
    output logic                   lsq_full,
    output logic                   lsq_empty,
    output logic                   lsq_ready_to_commit
);
    parameter LSQ_DEPTH = 8;
    import cpu_types_pkg::*;
    import config_pkg::*;

    typedef struct packed {
        lsu_dispatch_packet_t data;
        logic                 busy;
    } lsq_entry_t;

    lsq_entry_t           internal_queue[LSQ_DEPTH];
    mem_access_state_t    mem_state[LSQ_DEPTH];
    logic [31:0]          load_read_data[LSQ_DEPTH];
    
    logic [$clog2(LSQ_DEPTH)-1:0] head_ptr;
    logic [$clog2(LSQ_DEPTH)-1:0] tail_ptr;
    logic [$clog2(LSQ_DEPTH):0]   count;
    
    assign lsq_full = (count == LSQ_DEPTH);
    assign lsq_empty = (count == 0);
    
    logic forwarded;
    logic [31:0] forwarded_data;
    
    always_comb begin
        logic is_load_at_head;
        logic is_store_at_head;

        mem_read_en         = 1'b0;
        mem_address_out     = '0;
        mem_write_data_out  = '0;
        mem_write_en        = 1'b0;
        reg_write_en        = 1'b0;
        reg_write_addr      = '0;
        reg_write_data      = '0;
        lsq_ready_to_commit = 1'b0;
        forwarded           = 1'b0;
        forwarded_data      = '0;

        if (!lsq_empty && internal_queue[head_ptr].busy) begin
            is_load_at_head  = (internal_queue[head_ptr].data.opcode[7:5] == 3'b001); // Load
            is_store_at_head = (internal_queue[head_ptr].data.opcode[7:5] == 3'b010); // Store

            // Store-to-Load Forwarding Logic
            if (is_load_at_head && internal_queue[head_ptr].data.addr_op_is_ready) begin
                for (int i = 0; i < LSQ_DEPTH; i++) begin
                     // Check if valid store
                    if (internal_queue[i].busy &&
                        (internal_queue[i].data.opcode[7:5] == 3'b010) && // Is Store
                        (internal_queue[i].data.lsq_idx < internal_queue[head_ptr].data.lsq_idx) && // Is Older
                        internal_queue[i].data.addr_op_is_ready &&
                        internal_queue[i].data.data_op_is_ready &&
                        (internal_queue[head_ptr].data.addr_op_val == internal_queue[i].data.addr_op_val)) begin
                        
                        forwarded       = 1'b1;
                        forwarded_data  = internal_queue[i].data.data_op_val;
                    end
                end
            end
            
            // Memory Access Logic
            if (mem_state[head_ptr] == MEM_IDLE && !forwarded) begin
                if (is_load_at_head && internal_queue[head_ptr].data.addr_op_is_ready) begin
                    mem_read_en     = 1'b1;
                    mem_address_out = internal_queue[head_ptr].data.addr_op_val;
                end else if (is_store_at_head && internal_queue[head_ptr].data.addr_op_is_ready && internal_queue[head_ptr].data.data_op_is_ready) begin
                    mem_write_en       = 1'b1;
                    mem_address_out    = internal_queue[head_ptr].data.addr_op_val;
                    mem_write_data_out = internal_queue[head_ptr].data.data_op_val;
                end
            end

            if (mem_state[head_ptr] == MEM_COMPLETE || forwarded) begin
                lsq_ready_to_commit = 1'b1;
                if (is_load_at_head) begin
                    reg_write_en   = 1'b1;
                    reg_write_addr = internal_queue[head_ptr].data.dest_reg;
                    reg_write_data = forwarded ? forwarded_data : load_read_data[head_ptr];
                end
            end
        end
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            head_ptr <= 0;
            tail_ptr <= 0;
            count    <= 0;
            for (int i = 0; i < LSQ_DEPTH; i++) begin
                internal_queue[i].busy <= 1'b0;
                mem_state[i]           <= MEM_IDLE;
                load_read_data[i]      <= '0;
            end
        end else begin
            // Enqueue
            if (dispatch_to_ls_rs && !lsq_full) begin
                internal_queue[tail_ptr].data <= enqueue_data;
                internal_queue[tail_ptr].busy <= 1'b1;
                mem_state[tail_ptr]           <= MEM_IDLE;
                tail_ptr                      <= (tail_ptr + 1) % LSQ_DEPTH;
                count                         <= count + 1;
            end
            
            // State Update
            if (!lsq_empty && internal_queue[head_ptr].busy) begin
                if (forwarded) begin
                    mem_state[head_ptr] <= MEM_COMPLETE;
                end else begin
                    case (mem_state[head_ptr])
                        MEM_IDLE: begin
                            if (mem_read_en || mem_write_en) mem_state[head_ptr] <= MEM_ACCESSING;
                        end
                        MEM_ACCESSING: begin
                            if (mem_operation_complete_i) begin
                                if (internal_queue[head_ptr].data.opcode[7:5] == 3'b001) begin // Load
                                    load_read_data[head_ptr] <= mem_read_data_in;
                                end
                                mem_state[head_ptr] <= MEM_COMPLETE;
                            end
                        end
                        default:;
                    endcase
                end
            end
            
            // Commit / Dequeue
            if (ls_enable && lsq_ready_to_commit) begin
                internal_queue[head_ptr].busy <= 1'b0;
                mem_state[head_ptr]           <= MEM_IDLE;
                load_read_data[head_ptr]      <= '0;
                head_ptr                      <= (head_ptr + 1) % LSQ_DEPTH;
                count                         <= count - 1;
            end
        end
    end
endmodule