
module instruction_queue_top (
    input clk,
    input reset,
    input enqueue_valid,
    input instruction_queue_packet_t enqueue_data,
    output logic dequeue_valid,
    output instruction_queue_packet_t dequeue_data,
    input dequeue_request,
    output logic [3:0] queue_occupancy,
    output logic queue_full
);
    import cpu_types_pkg::*;

    parameter IQ_DEPTH = 8;
    instruction_queue_packet_t iq_entries[IQ_DEPTH];
    logic [2:0] head;
    logic [2:0] tail;
    logic [3:0] count;

    assign dequeue_valid = (count > 0);
    assign dequeue_data = iq_entries[head]; 
    assign queue_full = (count == IQ_DEPTH);
    assign queue_occupancy = count;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            head <= 3'b0;
            tail <= 3'b0;
            count <= 4'b0;
        end else begin
            logic enq_op, deq_op;

            enq_op = enqueue_valid && !queue_full;
            deq_op = dequeue_request && dequeue_valid;

            if (enq_op) begin
                iq_entries[tail] <= enqueue_data;
                tail <= (tail + 1);
            end

            if (deq_op) begin
                head <= (head + 1);
            end

            if (enq_op && !deq_op) begin
                count <= count + 1;
            end else if (deq_op && !enq_op) begin
                count <= count - 1;
            end
            // If both happen, count stays same
        end
    end
endmodule