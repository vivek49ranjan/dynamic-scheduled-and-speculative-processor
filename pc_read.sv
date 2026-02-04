module pc_reader (
    input  logic        clock, reset,
    input  logic [9:0]  pc_in,
    input  logic        start_fetch,
    output logic        busy,
    output logic        instruction_valid,
    output logic [31:0] instruction_out,
    
    output logic        mem_read_en,
    output logic [9:0]  mem_address_in,
    output logic        pc_req,           
    input  logic [31:0] mem_data_out,
    input  logic        mem_operation_complete,
    input  logic        mem_ready      
);
    typedef enum logic [1:0] { IDLE, FETCH, DONE } state_t;
    state_t current_state, next_state;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            current_state   <= IDLE;
            instruction_out <= 32'b0;
        end else begin
            current_state <= next_state;
            if (current_state == FETCH && mem_operation_complete)
                instruction_out <= mem_data_out;
        end
    end

    always_comb begin
        next_state        = current_state;
        busy              = 1'b1;
        instruction_valid = 1'b0;
        mem_read_en       = 1'b0;
        pc_req            = 1'b0;
        mem_address_in    = pc_in;

        case (current_state)
            IDLE: begin
                busy = 1'b0;
                if (start_fetch && mem_ready) next_state = FETCH;
            end
            FETCH: begin
                mem_read_en = 1'b1;
                pc_req      = 1'b1; 
                if (mem_operation_complete) next_state = DONE;
            end
            DONE: begin
                instruction_valid = 1'b1;
                next_state        = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
endmodule
