module instruction_queue (
    input  logic        clk, reset,
    input  logic        flush, 
	 
    input  logic        enqueue_valid,
    input  logic [52:0] enqueue_data,    
	 
    output logic        dequeue_valid,
    output logic [52:0] dequeue_data,    
    input  logic        dequeue_request,
	 
    output logic        queue_full
);

    parameter IQ_DEPTH = 64;
    
    logic [52:0] iq_entries[IQ_DEPTH];
    logic [5:0]  head, tail;
    logic [6:0]  count; 

    logic empty;
    assign empty           = (count == 0);
    assign queue_full      = (count == IQ_DEPTH[6:0]);
    assign dequeue_valid = !empty || enqueue_valid;
    assign dequeue_data  = empty ? enqueue_data : iq_entries[head];

    logic do_enq, do_deq;
    assign do_enq = enqueue_valid && !queue_full;
    assign do_deq = dequeue_request && dequeue_valid; 

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            head  <= 6'b0;
            tail  <= 6'b0;
            count <= 7'b0;
        end else if (flush) begin
            head  <= 6'b0;
            tail  <= 6'b0;
            count <= 7'b0;
        end else begin
            if (do_enq) begin
                iq_entries[tail] <= enqueue_data;
                tail <= tail + 1;
            end
            
            if (do_deq) begin
                head <= head + 1;
            end

            case ({do_enq, do_deq})
                2'b10: count <= count + 7'd1;
                2'b01: count <= count - 7'd1;
                default: count <= count; 
            endcase
        end
    end
endmodule
