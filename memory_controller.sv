module mem_controller (
    input  logic        clock, reset,
    input  logic [9:0]  instr_addr,
    input  logic        instr_read_en,
    output logic [31:0] instr_data_out,
    output logic        instr_valid,
    output logic        pc_ready,
    input  logic        pc_req,
    input  logic [9:0]  data_mem_addr,
    input  logic [31:0] data_write_val,
    input  logic        data_read_write,
    input  logic        read_write_req,
    output logic [31:0] data_read_val,
    output logic        data_valid,
    output logic        mux_en, mux_rw,
    output logic [9:0]  mux_addr,
    output logic [31:0] mux_write_data,
    input  logic [31:0] mem_data_out,
    input  logic        mem_done
);

    
    assign pc_ready = reset ? 1'b1 : !read_write_req;

    assign instr_data_out = mem_data_out;
    assign data_read_val  = mem_data_out;

   
    assign instr_valid = mem_done && !read_write_req && pc_req;
    assign data_valid  = mem_done && read_write_req;

    always_comb begin
        mux_en = 1'b0; 
        mux_addr = 10'b0; 
        mux_rw = 1'b1; 
        mux_write_data = 32'b0;

        if (read_write_req) begin
            mux_en         = 1'b1; 
            mux_addr       = data_mem_addr; 
            mux_rw         = data_read_write; 
            mux_write_data = data_write_val;
        end 
        else if (pc_req && instr_read_en) begin
            mux_en         = 1'b1; 
            mux_addr       = instr_addr; 
            mux_rw         = 1'b1; 
        end
    end
endmodule
