module memory (
    input logic clock, reset, read1,
    input logic [9:0] address1,
    output logic [8:0] data1, output logic first_ready,
    input logic read2,
    input logic [9:0] address2,
    output logic [8:0] data2, output logic second_ready,
    input logic write,
    input logic [9:0] write_address,
    input logic [8:0] write_data,
    output logic write_done
);
    logic [8:0] mem [0:1023];
    logic [8:0] data1_reg, data2_reg;
    logic first_ready_reg, second_ready_reg, write_done_reg;

    assign data1 = data1_reg; assign data2 = data2_reg;
    assign first_ready = first_ready_reg; assign second_ready = second_ready_reg;
    assign write_done = write_done_reg;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            data1_reg <= 9'b0; data2_reg <= 9'b0;
            first_ready_reg <= 1'b0; second_ready_reg <= 1'b0; write_done_reg <= 1'b0;
        end else begin
            first_ready_reg <= 1'b0; second_ready_reg <= 1'b0; write_done_reg <= 1'b0;
            if (read1) begin data1_reg <= mem[address1]; first_ready_reg <= 1'b1; end
            if (read2) begin data2_reg <= mem[address2]; second_ready_reg <= 1'b1; end
            if (write) begin mem[write_address] <= write_data; write_done_reg <= 1'b1; end
        end
    end
endmodule

