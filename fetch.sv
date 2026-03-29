module i_f (
    input  logic        clock, reset,
    input  logic        stall,              
    input  logic        flush_en,
    input  logic [9:0]  flush_target,
    input  logic        bp_train_en,
    input  logic [9:0]  bp_train_pc, 
    input  logic        bp_train_taken,
    input  logic [9:0]  bp_train_target,
    input  logic [31:0] instruction_mem_data,
    input  logic        instruction_valid,
    input  logic        queue_full,
    
    output logic        enqueue_valid,      
    output logic [41:0] fetch_packet_o,    
    output logic        predict_taken_o,   
    output logic [9:0]  predict_target_o,  
    output logic        start_fetch,
    output logic [9:0]  pc_to_reader,
    
    input  logic        ext_pc_set,
    input  logic [9:0]  ext_pc_val
);

    logic [9:0] pc;
    logic       predict_taken;
    logic [9:0] predict_target;
    logic       advance_pc;

    branch_predictor #(.INDEX_BITS(8)) bp (
        .clock(clock), .reset(reset),
        .fetch_pc(pc),
        .predict_taken(predict_taken), 
        .predict_target(predict_target),
        .update_en(bp_train_en), 
        .update_pc(bp_train_pc),         
        .update_actual_taken(bp_train_taken),    
        .update_target(bp_train_target)
    );

    assign pc_to_reader = pc;
    assign start_fetch  = 1'b1;
    assign advance_pc = instruction_valid && !queue_full && !stall && !flush_en && !ext_pc_set;

    always_comb begin
        enqueue_valid    = 1'b0;
        fetch_packet_o   = 42'd0;
        predict_taken_o  = 1'b0;
        predict_target_o = 10'd0;

        if (advance_pc && instruction_mem_data != 32'd0) begin
            enqueue_valid    = 1'b1;
            fetch_packet_o   = {pc, instruction_mem_data}; 
            predict_taken_o  = predict_taken;
            predict_target_o = predict_target;
        end
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            pc <= 10'd0;
        end 
        else if (ext_pc_set) begin
            pc <= ext_pc_val;
        end 
        else if (flush_en) begin
            pc <= flush_target;
        end 
        else if (advance_pc) begin
            pc <= predict_taken ? predict_target : pc + 10'd1;
        end
    end
endmodule

module branch_predictor #(
    parameter INDEX_BITS = 8
)(
    input  logic        clock,
    input  logic        reset,
    input  logic [9:0]  fetch_pc,
    output logic        predict_taken,
    output logic [9:0]  predict_target,
    
    input  logic        update_en,
    input  logic [9:0]  update_pc,
    input  logic        update_actual_taken,
    input  logic [9:0]  update_target
);

    logic [1:0] bht [(1<<INDEX_BITS)-1:0];
    logic [9:0] btb [(1<<INDEX_BITS)-1:0];
    logic [INDEX_BITS-1:0] fetch_idx;
    logic [INDEX_BITS-1:0] update_idx;

    assign fetch_idx  = fetch_pc[INDEX_BITS-1:0];
    assign update_idx = update_pc[INDEX_BITS-1:0];
    
    assign predict_taken  = bht[fetch_idx][1];
    assign predict_target = btb[fetch_idx];

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < (1<<INDEX_BITS); i++) begin
                bht[i] <= 2'b01; 
                btb[i] <= 10'd0;
            end
        end
        else if (update_en) begin
            btb[update_idx] <= update_target;
            case (bht[update_idx])
                2'b00: bht[update_idx] <= update_actual_taken ? 2'b01 : 2'b00;
                2'b01: bht[update_idx] <= update_actual_taken ? 2'b10 : 2'b00;
                2'b10: bht[update_idx] <= update_actual_taken ? 2'b11 : 2'b01;
                2'b11: bht[update_idx] <= update_actual_taken ? 2'b11 : 2'b10;
            endcase
        end
    end
endmodule
