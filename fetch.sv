module i_f (
    input  logic        clock, reset,
    input  logic        stall,              
    input  logic        branch_taken,
    input  logic [9:0]  branch_target,
    input  logic [31:0] instruction_mem_data,
    input  logic        instruction_valid,
    input  logic        queue_full,
    
    output logic        enqueue_valid,      
    output logic [41:0] fetch_packet_o,    
    output logic        start_fetch,
    output logic [9:0]  pc_to_reader,
    input  logic        ext_pc_set,
    input  logic [9:0]  ext_pc_val
);

    logic [9:0] pc;
    logic [9:0] pc_delayed; 
    logic       fetch_pending;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            pc            <= 10'd0;
            pc_delayed    <= 10'd0;
            fetch_pending <= 1'b0;
            enqueue_valid <= 1'b0;
            fetch_packet_o <= 42'd0;
        end else begin
            if (ext_pc_set || branch_taken) begin
                pc            <= ext_pc_set ? ext_pc_val : branch_target;
                fetch_pending <= 1'b0;
                enqueue_valid <= 1'b0;
            end else begin
                if (instruction_valid && !queue_full) begin
                    enqueue_valid  <= 1'b1;
                    fetch_packet_o <= {pc_delayed, instruction_mem_data}; 
                    fetch_pending  <= 1'b0;
                end else begin
                    enqueue_valid  <= 1'b0;
                end

                if (!stall && !fetch_pending && !queue_full) begin
                    pc_to_reader  <= pc;
                    pc_delayed    <= pc; 
                    pc            <= pc + 10'd1;
                    fetch_pending <= 1'b1;
                    start_fetch   <= 1'b1;
                end else begin
                    start_fetch   <= 1'b0;
                end
            end
        end
    end
endmodule
