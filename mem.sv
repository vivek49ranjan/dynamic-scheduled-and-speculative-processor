module memory_stage (
    input  clock, reset,
    input  logic        mem_read_en, mem_write_en,
    input  logic [9:0]  mem_address_in,
    input  logic [31:0] mem_write_data_in,
    output logic [31:0] mem_data_out,
    output logic        mem_operation_complete,
    
    // Interface to physical RAM
    output logic        enable_ram_read, enable_ram_write,
    output logic [9:0]  ram_address_out,
    output logic [31:0] ram_write_data_out,
    input  logic        ram_busy,
    input  logic [31:0] ram_data_in,
    input  logic        ram_data_available
);
    typedef enum bit [1:0] { IDLE, ACCESS, DONE } state_t;
    state_t current_state, next_state;
    logic [9:0] address_reg; logic [31:0] write_data_reg; logic is_read_op_reg;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            current_state <= IDLE; mem_data_out <= 32'b0;
            address_reg <= '0; write_data_reg <= '0; is_read_op_reg <= 1'b0;
        end else begin
            current_state <= next_state;
            if (current_state == IDLE && (mem_read_en || mem_write_en)) begin
                address_reg <= mem_address_in; write_data_reg <= mem_write_data_in; is_read_op_reg <= mem_read_en;
            end
            if (current_state == ACCESS && is_read_op_reg && ram_data_available) begin
                mem_data_out <= ram_data_in;
            end
        end
    end

    always_comb begin
        next_state = current_state; enable_ram_read = 1'b0; enable_ram_write = 1'b0;
        ram_address_out = address_reg; ram_write_data_out = write_data_reg; mem_operation_complete = 1'b0;

        case (current_state)
            IDLE: if (mem_read_en || mem_write_en) next_state = ACCESS;
            ACCESS: begin
                if (is_read_op_reg) begin
                    enable_ram_read = 1'b1;
                    if (ram_data_available) next_state = DONE;
                end else begin
                    enable_ram_write = 1'b1;
                    if (!ram_busy) next_state = DONE;
                end
            end
            DONE: begin mem_operation_complete = 1'b1; next_state = IDLE; end
            default: next_state = IDLE;
        endcase
    end
endmodule