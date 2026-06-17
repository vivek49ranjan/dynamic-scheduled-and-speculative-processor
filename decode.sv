import config_pkg::*;
import cpu_types_pkg::*;

module decode ( 
    input  logic                clock,
    input  logic                reset,
    
    input  logic                if_id_valid,        
    input  logic                if_id_pred_taken,  
    input  logic [9:0]          if_id_pred_target, 
    input  logic [9:0]          if_id_pc,
    input  logic [31:0]         if_id_opcode,
    
    input  logic                stall,             
    input  logic                flush,             
    
    output logic                id_valid,
    output decoded_instruction_t decoded_instruction
);

    logic [6:0] rv_opcode;
    logic [4:0] rv_rd, rv_rs1, rv_rs2;
    logic [2:0] rv_funct3;
    logic [6:0] rv_funct7;

    decoded_instruction_t next_decoded_instruction;

    assign rv_opcode = if_id_opcode[6:0];
    assign rv_rd     = if_id_opcode[11:7];
    assign rv_funct3 = if_id_opcode[14:12];
    assign rv_rs1    = if_id_opcode[19:15];
    assign rv_rs2    = if_id_opcode[24:20];
    assign rv_funct7 = if_id_opcode[31:25];

   
    always_comb begin
        next_decoded_instruction = '0;

        if (if_id_valid && (if_id_opcode != 32'd0)) begin
            next_decoded_instruction.pc               = if_id_pc;
            next_decoded_instruction.operand1_reg     = rv_rs1;  
            next_decoded_instruction.operand2_reg     = 5'd0; 
            next_decoded_instruction.result_reg       = rv_rd; 
            next_decoded_instruction.predicted_taken  = if_id_pred_taken;  
            next_decoded_instruction.predicted_target = if_id_pred_target; 

            case (rv_opcode)
                RV32_OP: begin
                    next_decoded_instruction.instr_type   = INSTR_ALU;
                    next_decoded_instruction.immediate    = 32'b0;
                    next_decoded_instruction.operand2_reg = rv_rs2; 
                    case (rv_funct3)
                        3'b000:  next_decoded_instruction.opcode = (rv_funct7[5]) ? OPCODE_SUB : OPCODE_ADD;
                        3'b001:  next_decoded_instruction.opcode = OPCODE_SLL;
                        3'b010:  next_decoded_instruction.opcode = OPCODE_COMPARE; 
                        3'b011:  next_decoded_instruction.opcode = OPCODE_COMPARE; 
                        3'b100:  next_decoded_instruction.opcode = OPCODE_XOR;
                        3'b101:  next_decoded_instruction.opcode = (rv_funct7[5]) ? OPCODE_SRA : OPCODE_SRL;
                        3'b110:  next_decoded_instruction.opcode = OPCODE_OR;
                        3'b111:  next_decoded_instruction.opcode = OPCODE_AND;
                        default: next_decoded_instruction.opcode = OPCODE_ADD;
                    endcase
                end
                
                RV32_OP_IMM: begin
                    next_decoded_instruction.instr_type = INSTR_ALU;
                    next_decoded_instruction.immediate  = {{20{if_id_opcode[31]}}, if_id_opcode[31:20]}; 
                    case (rv_funct3)
                        3'b000:  next_decoded_instruction.opcode = OPCODE_ADDI; 
                        3'b001:  next_decoded_instruction.opcode = OPCODE_SLLI;     
                        3'b010:  next_decoded_instruction.opcode = OPCODE_COMPARE; 
                        3'b011:  next_decoded_instruction.opcode = OPCODE_COMPARE; 
                        3'b100:  next_decoded_instruction.opcode = OPCODE_XORI;     
                        3'b101:  next_decoded_instruction.opcode = (rv_funct7[5]) ? OPCODE_SRAI : OPCODE_SRLI;
                        3'b110:  next_decoded_instruction.opcode = OPCODE_ORI;     
                        3'b111:  next_decoded_instruction.opcode = OPCODE_ANDI;     
                        default: next_decoded_instruction.opcode = OPCODE_ADDI;
                    endcase
                end
                
                RV32_LOAD: begin
                    next_decoded_instruction.instr_type = INSTR_LOAD;
                    next_decoded_instruction.opcode     = OPCODE_LOAD;
                    next_decoded_instruction.immediate  = {{20{if_id_opcode[31]}}, if_id_opcode[31:20]};
                end 
                
                RV32_STORE: begin
                    next_decoded_instruction.instr_type   = INSTR_STORE;
                    next_decoded_instruction.opcode       = OPCODE_STORE;
                    next_decoded_instruction.operand2_reg = rv_rs2; 
                    next_decoded_instruction.result_reg   = 5'd0; 
                    next_decoded_instruction.immediate    = {{20{if_id_opcode[31]}}, if_id_opcode[31:25], if_id_opcode[11:7]};
                end 
                
                RV32_BRANCH: begin
                    next_decoded_instruction.instr_type   = INSTR_BRANCH;
                    next_decoded_instruction.operand2_reg = rv_rs2; 
                    next_decoded_instruction.result_reg   = 5'd0; 
                    next_decoded_instruction.immediate    = {{20{if_id_opcode[31]}}, if_id_opcode[7], if_id_opcode[30:25], if_id_opcode[11:8], 1'b0};
                    case (rv_funct3)
                        3'b000:  next_decoded_instruction.opcode = JE;
                        3'b001:  next_decoded_instruction.opcode = JNE;
                        3'b100:  next_decoded_instruction.opcode = JLT;
                        3'b101:  next_decoded_instruction.opcode = JGE;
                        3'b110:  next_decoded_instruction.opcode = JLTU;
                        3'b111:  next_decoded_instruction.opcode = JGEU;
                        default: next_decoded_instruction.opcode = JE;
                    endcase
                end
                
                RV32_LUI: begin
                    next_decoded_instruction.instr_type   = INSTR_ALU; 
                    next_decoded_instruction.opcode       = OPCODE_ADDI; 
                    next_decoded_instruction.operand1_reg = 5'd0; 
                    next_decoded_instruction.operand2_reg = 5'd0; 
                    next_decoded_instruction.result_reg   = rv_rd;
                    next_decoded_instruction.immediate    = {if_id_opcode[31:12], 12'b0}; 
                end

                RV32_AUIPC: begin
                    next_decoded_instruction.instr_type   = INSTR_ALU; 
                    next_decoded_instruction.opcode       = OPCODE_ADDI;
                    next_decoded_instruction.operand1_reg = 5'd0; 
                    next_decoded_instruction.operand2_reg = 5'd0; 
                    next_decoded_instruction.result_reg   = rv_rd;
                    next_decoded_instruction.immediate    = {20'd0, if_id_pc, 2'b00} + {if_id_opcode[31:12], 12'b0}; 
                end

                RV32_JAL: begin
                    next_decoded_instruction.instr_type   = INSTR_ALU; 
                    next_decoded_instruction.opcode       = JAL;  
                    next_decoded_instruction.operand1_reg = 5'd0; 
                    next_decoded_instruction.operand2_reg = 5'd0; 
                    next_decoded_instruction.result_reg   = rv_rd; 
                    next_decoded_instruction.immediate    = {{12{if_id_opcode[31]}}, if_id_opcode[19:12], if_id_opcode[20], if_id_opcode[30:21], 1'b0};
                end

                RV32_JALR: begin
                    next_decoded_instruction.instr_type   = INSTR_ALU; 
                    next_decoded_instruction.opcode       = JALR; 
                    next_decoded_instruction.operand1_reg = rv_rs1; 
                    next_decoded_instruction.operand2_reg = 5'd0; 
                    next_decoded_instruction.result_reg   = rv_rd; 
                    next_decoded_instruction.immediate    = {{20{if_id_opcode[31]}}, if_id_opcode[31:20]};
                end

                default: begin
                    next_decoded_instruction.instr_type = INSTR_OTHER;
                    next_decoded_instruction.opcode     = 8'h00;
                    next_decoded_instruction.immediate  = 32'b0;
                end
            endcase
        end
    end

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            id_valid            <= 1'b0;
            decoded_instruction <= '0;
        end 
        else if (flush) begin
            id_valid            <= 1'b0;
            decoded_instruction <= '0;
        end 
        else if (!stall) begin
            if (if_id_valid && (if_id_opcode != 32'd0)) begin
                id_valid            <= 1'b1;
                decoded_instruction <= next_decoded_instruction;
            end else begin
                id_valid            <= 1'b0;
                decoded_instruction <= '0; 
            end
        end
    end

endmodule
