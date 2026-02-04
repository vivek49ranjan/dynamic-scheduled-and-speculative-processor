module register (
    input  logic        clock, reset,
    input  logic        read_en,        
    input  logic        write_enable,   
    
    input  logic [4:0]  read_addr1,
    output logic [31:0] read_data1,
    
    input  logic [4:0]  read_addr2,
    output logic [31:0] read_data2,
    
    input  logic [4:0]  write,
    input  logic [31:0] write_data
);
    logic [31:0] reg_file [31:0];

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < 32; i++) begin
                reg_file[i] <= 32'b0;
            end
        end else if (write_enable && write != 5'b0) begin
            reg_file[write] <= write_data;
        end
    end

   
    assign read_data1 = (read_addr1 == 5'b0) ? 32'b0 : reg_file[read_addr1];
    assign read_data2 = (read_addr2 == 5'b0) ? 32'b0 : reg_file[read_addr2];

endmodule
