module pc_reader (
    input  logic        clock,
    input  logic        reset,
    input  logic [9:0]  pc_in,
    input  logic        start_fetch,
    output logic        busy,
    output logic        instruction_valid,
    output logic [31:0] instruction_out,
    output logic        mem_read_en,
    output logic [9:0]  mem_address_in,
    input  logic [31:0] mem_data_out,
    input  logic        mem_operation_complete
);
    typedef enum bit [1:0] {
        IDLE,
        FETCH,
        DONE
    } state_t;

    state_t current_state, next_state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            current_state   <= IDLE;
            instruction_out <= 32'b0;
        end else begin
            current_state <= next_state;
            if (current_state == FETCH && mem_operation_complete) begin
                instruction_out <= mem_data_out;
            end
        end
    end

    always_comb begin
        next_state        = current_state;
        busy              = 1'b1;
        instruction_valid = 1'b0;
        mem_read_en       = 1'b0;
        mem_address_in    = pc_in;

        case (current_state)
            IDLE: begin
                busy = 1'b0;
                if (start_fetch) begin
                    next_state = FETCH;
                end
            end
            FETCH: begin
                mem_read_en = 1'b1;
                if (mem_operation_complete) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                instruction_valid = 1'b1;
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
endmodule
