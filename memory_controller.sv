module mem_controller (
    input  clock,
    input  reset,
    input  [9:0]  pc,
    output logic [31:0] opcode,
    input  [9:0]  mem_Raddrs,
    input  [9:0]  mem_Waddrs,
    input  [31:0] write_data,
    output logic [31:0] read1_data,
    input  read1_en,
    input  read2_en,
    input  write_en
);
    logic [8:0] b1_data1, b2_data1, b3_data1, b4_data1;
    logic b1_first_ready, b2_first_ready, b3_first_ready, b4_first_ready;
    logic [8:0] b1_data2, b2_data2, b3_data2, b4_data2;
    logic b1_second_ready, b2_second_ready, b3_second_ready, b4_second_ready;
    logic b1_write_done, b2_write_done, b3_write_done, b4_write_done;

    assign opcode = {b4_data1[7:0], b3_data1[7:0], b2_data1[7:0], b1_data1[7:0]};
    assign read1_data = {b4_data2[7:0], b3_data2[7:0], b2_data2[7:0], b1_data2[7:0]};

    // Instantiate 4 byte-banks
    memory block1 (.clock(clock), .reset(reset), .read1(read1_en), .address1(pc), .data1(b1_data1), .first_ready(b1_first_ready), .read2(read2_en), .address2(mem_Raddrs), .data2(b1_data2), .second_ready(b1_second_ready), .write(write_en), .write_address(mem_Waddrs), .write_data(write_data[7:0]), .write_done(b1_write_done));
    memory block2 (.clock(clock), .reset(reset), .read1(read1_en), .address1(pc), .data1(b2_data1), .first_ready(b2_first_ready), .read2(read2_en), .address2(mem_Raddrs), .data2(b2_data2), .second_ready(b2_second_ready), .write(write_en), .write_address(mem_Waddrs), .write_data(write_data[15:8]), .write_done(b2_write_done));
    memory block3 (.clock(clock), .reset(reset), .read1(read1_en), .address1(pc), .data1(b3_data1), .first_ready(b3_first_ready), .read2(read2_en), .address2(mem_Raddrs), .data2(b3_data2), .second_ready(b3_second_ready), .write(write_en), .write_address(mem_Waddrs), .write_data(write_data[23:16]), .write_done(b3_write_done));
    memory block4 (.clock(clock), .reset(reset), .read1(read1_en), .address1(pc), .data1(b4_data1), .first_ready(b4_first_ready), .read2(read2_en), .address2(mem_Raddrs), .data2(b4_data2), .second_ready(b4_second_ready), .write(write_en), .write_address(mem_Waddrs), .write_data(write_data[31:24]), .write_done(b4_write_done));
endmodule
