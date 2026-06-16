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
