
module lsu_functional_unit (
    input  logic        clock, reset,
    
    input  logic        fu_issue_valid,
    input  logic        fu_issue_is_load,
    input  logic [9:0]  fu_issue_addr,
    input  logic [31:0] fu_issue_data,
    input  logic [4:0]  fu_issue_rob_tag,
    input  logic        fu_issue_fwd_valid,
    input  logic [31:0] fu_issue_fwd_data,
    
    input  logic        fu_commit_store_valid,
    input  logic [9:0]  fu_commit_store_addr,
    input  logic [31:0] fu_commit_store_data,
    
    output logic        fu_busy_o,
    output logic [4:0]  fu_active_rob_tag_o,
    
    output logic [9:0]  data_mem_addr,
    output logic [31:0] data_mem_write_data,
    output logic        data_mem_read_write,
    output logic        data_mem_req,
    input  logic        data_mem_valid,      
    input  logic [31:0] data_mem_data_i,     
    
    output logic [31:0] lsu_cdb_value,
    output logic [4:0]  lsu_cdb_rob_tag,      
    output logic        lsu_cdb_valid,
    
    output logic        lsq_store_done_o
);

    logic mem_busy;
    logic [4:0] mem_active_rob_tag;
    logic store_commit_active;

    assign fu_busy_o = mem_busy;
    assign fu_active_rob_tag_o = mem_active_rob_tag;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            mem_busy <= 1'b0;
            data_mem_req <= 1'b0;
            lsu_cdb_valid <= 1'b0;
            lsq_store_done_o <= 1'b0;
            store_commit_active <= 1'b0;
            mem_active_rob_tag <= 5'd0;
        end else begin
            lsu_cdb_valid <= 1'b0;
            data_mem_req  <= 1'b0;
            lsq_store_done_o <= 1'b0;

            if (data_mem_valid && mem_busy) begin
                mem_busy <= 1'b0;
                if (store_commit_active) begin
                    store_commit_active <= 1'b0;
                    lsq_store_done_o    <= 1'b1; 
                end else begin
                    lsu_cdb_valid   <= 1'b1;
                    lsu_cdb_rob_tag <= mem_active_rob_tag;
                    lsu_cdb_value   <= data_mem_data_i; 
                end
            end

            if (fu_commit_store_valid && !mem_busy && !store_commit_active) begin
                mem_busy            <= 1'b1;
                store_commit_active <= 1'b1;
                data_mem_req        <= 1'b1;
                data_mem_read_write <= 1'b0; 
                data_mem_addr       <= fu_commit_store_addr;
                data_mem_write_data <= fu_commit_store_data;
            end 
            else if (fu_issue_valid && !mem_busy) begin
                if (!fu_issue_is_load) begin
                    lsu_cdb_valid   <= 1'b1;
                    lsu_cdb_rob_tag <= fu_issue_rob_tag;
                    lsu_cdb_value   <= 32'd0;
                end else if (fu_issue_fwd_valid) begin
                    lsu_cdb_valid   <= 1'b1;
                    lsu_cdb_rob_tag <= fu_issue_rob_tag;
                    lsu_cdb_value   <= fu_issue_fwd_data; 
                end else begin
                    mem_busy            <= 1'b1;
                    mem_active_rob_tag  <= fu_issue_rob_tag;
                    data_mem_req        <= 1'b1;
                    data_mem_addr       <= fu_issue_addr;
                    data_mem_read_write <= 1'b1; 
                end
            end
        end
    end
endmodule
