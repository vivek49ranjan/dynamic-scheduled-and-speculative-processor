import config_pkg::*;
import cpu_types_pkg::*;
module decode ( 
    input  logic                clock,
    input  logic                reset,
    input  logic                if_id_valid,        
    input  logic [9:0]          if_id_pc,
    input  logic [31:0]         if_id_opcode,
    input  logic                stall,              
    input  logic                flush,              
    input  logic                dispatch_success_i, 
    
    output logic                id_valid,
    output logic [9:0]          id_pc,
    output decoded_instruction_t decoded_instruction
);

    decoded_instruction_t comb_dec;
    
    logic [6:0] rv_opcode;
    logic [4:0] rv_rd, rv_rs1, rv_rs2;
    logic [2:0] rv_funct3;
    logic [6:0] rv_funct7;

    always_comb begin
        comb_dec = '0; 
        
        rv_opcode = if_id_opcode[6:0];
        rv_rd     = if_id_opcode[11:7];
        rv_funct3 = if_id_opcode[14:12];
        rv_rs1    = if_id_opcode[19:15];
        rv_rs2    = if_id_opcode[24:20];
        rv_funct7 = if_id_opcode[31:25];

        comb_dec.operand1_reg = rv_rs1;  
        comb_dec.operand2_reg = 5'd0; 
        comb_dec.result_reg   = rv_rd; 
        comb_dec.pc           = if_id_pc;

        case (rv_opcode)
            RV32_OP: begin
                comb_dec.instr_type = INSTR_ALU;
                comb_dec.immediate  = 32'b0;
                comb_dec.operand2_reg = rv_rs2; 
                case (rv_funct3)
                    3'b000:  comb_dec.opcode = (rv_funct7[5]) ? OPCODE_SUB : OPCODE_ADD;
                    3'b001:  comb_dec.opcode = OPCODE_SLL;
                    3'b010:  comb_dec.opcode = OPCODE_COMPARE; 
                    3'b011:  comb_dec.opcode = OPCODE_COMPARE; 
                    3'b100:  comb_dec.opcode = OPCODE_XOR;
                    3'b101:  comb_dec.opcode = (rv_funct7[5]) ? OPCODE_SRA : OPCODE_SRL;
                    3'b110:  comb_dec.opcode = OPCODE_OR;
                    3'b111:  comb_dec.opcode = OPCODE_AND;
                    default: comb_dec.opcode = OPCODE_ADD;
                endcase
            end
            RV32_OP_IMM: begin
                comb_dec.instr_type = INSTR_ALU;
                comb_dec.immediate  = {{20{if_id_opcode[31]}}, if_id_opcode[31:20]}; 
                case (rv_funct3)
                    3'b000:  comb_dec.opcode = OPCODE_ADDI; 
                    3'b001:  comb_dec.opcode = OPCODE_SLL;     
                    3'b010:  comb_dec.opcode = OPCODE_COMPARE; 
                    3'b011:  comb_dec.opcode = OPCODE_COMPARE; 
                    3'b100:  comb_dec.opcode = OPCODE_XOR;     
                    3'b101:  comb_dec.opcode = (rv_funct7[5]) ? OPCODE_SRA : OPCODE_SRL;
                    3'b110:  comb_dec.opcode = OPCODE_OR;      
                    3'b111:  comb_dec.opcode = OPCODE_AND;     
                    default: comb_dec.opcode = OPCODE_ADDI;
                endcase
            end
            RV32_LOAD: begin
                comb_dec.instr_type       = INSTR_LOAD;
                comb_dec.opcode           = OPCODE_LOAD;
                comb_dec.load_destination = rv_rd;
                comb_dec.load_source      = rv_rs1;
                comb_dec.immediate        = {{20{if_id_opcode[31]}}, if_id_opcode[31:20]};
            end 
            RV32_STORE: begin
                comb_dec.instr_type        = INSTR_STORE;
                comb_dec.opcode            = OPCODE_STORE;
                comb_dec.store_source      = rv_rs2;
                comb_dec.store_destination = rv_rs1; 
                comb_dec.operand2_reg      = rv_rs2; 
                comb_dec.result_reg        = 5'd0; 
                comb_dec.immediate         = {{20{if_id_opcode[31]}}, if_id_opcode[31:25], if_id_opcode[11:7]};
            end 
            RV32_BRANCH: begin
                comb_dec.instr_type = INSTR_BRANCH;
                comb_dec.operand2_reg = rv_rs2; 
                comb_dec.result_reg   = 5'd0; 
                comb_dec.immediate  = {{20{if_id_opcode[31]}}, if_id_opcode[7], if_id_opcode[30:25], if_id_opcode[11:8], 1'b0};
                case (rv_funct3)
                    3'b000:  comb_dec.opcode = JE;
                    3'b001:  comb_dec.opcode = JNE;
                    3'b100:  comb_dec.opcode = JLT;
                    3'b101:  comb_dec.opcode = JGE;
                    3'b110:  comb_dec.opcode = JLTU;
                    3'b111:  comb_dec.opcode = JGEU;
                    default: comb_dec.opcode = JE;
                endcase
            end

            RV32_LUI, RV32_AUIPC: begin
                comb_dec.instr_type = INSTR_ALU; 
                comb_dec.opcode     = OPCODE_ADD; 
                comb_dec.immediate  = {if_id_opcode[31:12], 12'b0}; 
            end

            RV32_JAL: begin
                comb_dec.instr_type = INSTR_BRANCH; 
                comb_dec.opcode     = JE; 
                comb_dec.immediate  = {{12{if_id_opcode[31]}}, if_id_opcode[19:12], if_id_opcode[20], if_id_opcode[30:21], 1'b0};
            end

            RV32_JALR: begin
                comb_dec.instr_type = INSTR_BRANCH; 
                comb_dec.opcode     = JE;
                comb_dec.immediate  = {{20{if_id_opcode[31]}}, if_id_opcode[31:20]};
            end

            default: begin
                comb_dec.instr_type = (if_id_opcode == 32'b0) ? INSTR_OTHER : INSTR_ALU;
                comb_dec.opcode     = 8'h00;
                comb_dec.immediate  = 32'b0;
            end
        endcase
    end
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            id_pc               <= 10'd0;
            decoded_instruction <= '0;
            id_valid            <= 1'b0;
        end 
        else if (flush) begin
            id_pc               <= 10'd0;
            decoded_instruction <= '0;
            id_valid            <= 1'b0;
        end 
        else if (!stall) begin
            if (if_id_valid && (if_id_opcode != 32'd0)) begin
                id_pc               <= if_id_pc;
                decoded_instruction <= comb_dec; 
                id_valid            <= 1'b1;
            end else begin
                id_valid            <= 1'b0;
            end
        end
    end
endmodule
