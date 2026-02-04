import config_pkg::*;
import cpu_types_pkg::*;

module load_store_unit (
    input  logic          clock, reset,
    input  logic          lsu_dispatch_valid,
    input  lsu_dispatch_packet_t lsu_packet_i,
    output logic          rs_full_o,

    output logic [9:0]    data_mem_addr,
    output logic [31:0]   data_mem_write_data,
    output logic          data_mem_read_write, 
    output logic          data_mem_req,
    input  logic          data_mem_valid,      
    input  logic [31:0]   data_mem_data_i,     
    
    output logic [31:0]   lsu_cdb_value,
    output logic [4:0]    lsu_cdb_rob_tag,     
    output logic          lsu_cdb_valid
);

    typedef enum logic [1:0] { IDLE, BUSY, DONE } state_t;
    state_t state;
    lsu_dispatch_packet_t active_packet;

    assign rs_full_o = (state != IDLE);

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            data_mem_req <= 1'b0;
            lsu_cdb_valid <= 1'b0;
            {data_mem_addr, data_mem_write_data, data_mem_read_write} <= '0;
        end else begin
            lsu_cdb_valid <= 1'b0; 

            case (state)
                IDLE: begin
                    if (lsu_dispatch_valid && lsu_packet_i.addr_op_is_ready) begin
                        if (lsu_packet_i.opcode != 8'h04 || lsu_packet_i.data_op_is_ready) begin
                            active_packet <= lsu_packet_i;
                            data_mem_addr <= lsu_packet_i.addr_op_val[9:0];
                            data_mem_write_data <= lsu_packet_i.data_op_val;
                            data_mem_read_write <= (lsu_packet_i.opcode == 8'h03);
                            data_mem_req  <= 1'b1;
                            state         <= BUSY;
                        end
                    end
                end

                BUSY: begin
                    if (data_mem_valid) begin
                        data_mem_req    <= 1'b0;
                        lsu_cdb_valid   <= 1'b1;
                        lsu_cdb_rob_tag <= active_packet.rob_idx;
                        
                        lsu_cdb_value   <= (active_packet.opcode == 8'h03) ? data_mem_data_i : 32'h0;
                        state           <= DONE;
                    end
                end

                DONE: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
