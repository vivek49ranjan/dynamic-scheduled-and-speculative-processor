module register (
    input  logic        clock, 
    input  logic        reset,
    // Read Port 1
    input  logic        read1_en, 
    input  logic [4:0]  read1, 
    output logic [31:0] read1_data,
    // Read Port 2
    input  logic        read2_en, 
    input  logic [4:0]  read2, 
    output logic [31:0] read2_data,
    // Write Port
    input  logic        write_enable, 
    input  logic [4:0]  write, 
    input  logic [31:0] write_data
);
    // 32 architectural registers
    logic [31:0] reg_file [31:0];

    // --- Sequential Logic (Register Writes) ---
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < 32; i++) 
                reg_file[i] <= 32'b0;
            read1_data <= 32'b0; 
            read2_data <= 32'b0;
        end else begin
            // Synchronous Write: Write only if enabled and not writing to R0 (5'b0)
            if (write_enable && write != 5'b0) begin
                reg_file[write] <= write_data;
            end
            
            // Register Read Outputs (Read data is typically combinational, then registered for pipeline stability)
            // Here, the read data is registered based on the read enable signal.

            // Read Port 1: R0 reads zero
            if (read1_en) begin
                read1_data <= (read1 == 5'b0) ? 32'b0 : reg_file[read1];
            end
            
            // Read Port 2: R0 reads zero
            if (read2_en) begin
                read2_data <= (read2 == 5'b0) ? 32'b0 : reg_file[read2];
            end
        end
    end
endmodule
