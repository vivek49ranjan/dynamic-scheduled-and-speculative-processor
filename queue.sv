module instruction_queue (
    input  logic        clk, reset,
    input  logic        enqueue_valid,
    input  logic [41:0] enqueue_data,    
    output logic        dequeue_valid,
    output logic [41:0] dequeue_data,    
    input  logic        dequeue_request,
    output logic [5:0]  queue_occupancy,
    output logic        queue_full
);

    parameter IQ_DEPTH = 64;
    logic [41:0] iq_entries[IQ_DEPTH];
    logic [5:0] head, tail, count;

    assign dequeue_valid   = (count > 0);
    assign dequeue_data    = iq_entries[head]; 
    assign queue_full     = (count == IQ_DEPTH);
    assign queue_occupancy = count;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            head  <= 6'b0;
            tail  <= 6'b0;
            count <= 6'b0;
        end else begin
            bit enq, deq;
            enq = enqueue_valid && !queue_full;
            deq = dequeue_request && dequeue_valid;

            if (enq) begin
                iq_entries[tail] <= enqueue_data;
                tail <= tail + 1;
            end
            if (deq) begin
                head <= head + 1;
            end

            case ({enq, deq})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: count <= count; 
            endcase
        end
    end
endmodule
