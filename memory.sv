module memory (
    input  logic        clock, reset,
    input  logic        pc_en,
    input  logic [9:0]  pc_addr,
    output logic [31:0] pc_instr_out,
    output logic        pc_done,
    input  logic        data_en,
    input  logic        data_rw, 
    input  logic [9:0]  data_addr,
    input  logic [31:0] data_wdata,
    output logic [31:0] data_out,
    output logic        data_done
);
    logic [31:0] rom [0:1023];
    logic [31:0] ram [0:1023];

    initial begin
        $readmemh("program.hex", rom);
    end

    always_ff @(posedge clock) begin
        if (pc_en) begin
            pc_instr_out <= rom[pc_addr];
            pc_done      <= 1'b1;
        end else begin
            pc_done      <= 1'b0;
        end
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            data_out  <= 32'h0;
            data_done <= 1'b0;
            for (int i = 0; i < 1024; i++) ram[i] <= 32'h0;
        end else if (data_en) begin
            if (data_rw) data_out <= ram[data_addr];
            else         ram[data_addr] <= data_wdata;
            data_done <= 1'b1;
        end else begin
            data_done <= 1'b0;
        end
    end
endmodule
