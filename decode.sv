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

    assign rv_opcode = if_id_opcode[6:0];
    assign rv_rd     = if_id_opcode[11:7];
    assign rv_funct3 = if_id_opcode[14:12];
    assign rv_rs1    = if_id_opcode[19:15];
    assign rv_rs2    = if_id_opcode[24:20];
    assign rv_funct7 = if_id_opcode[31:25];

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
                id_valid <= 1'b1;
       
                decoded_instruction <= '0;
                
                decoded_instruction.pc               <= if_id_pc;
                decoded_instruction.operand1_reg     <= rv_rs1;  
                decoded_instruction.operand2_reg     <= 5'd0; 
                decoded_instruction.result_reg       <= rv_rd; 
                decoded_instruction.predicted_taken  <= if_id_pred_taken;  
                decoded_instruction.predicted_target <= if_id_pred_target; 

                case (rv_opcode)
                    RV32_OP: begin
                        decoded_instruction.instr_type   <= INSTR_ALU;
                        decoded_instruction.immediate    <= 32'b0;
                        decoded_instruction.operand2_reg <= rv_rs2; 
                        case (rv_funct3)
                            3'b000:  decoded_instruction.opcode <= (rv_funct7[5]) ? OPCODE_SUB : OPCODE_ADD;
                            3'b001:  decoded_instruction.opcode <= OPCODE_SLL;
                            3'b010:  decoded_instruction.opcode <= OPCODE_COMPARE; 
                            3'b011:  decoded_instruction.opcode <= OPCODE_COMPARE; 
                            3'b100:  decoded_instruction.opcode <= OPCODE_XOR;
                            3'b101:  decoded_instruction.opcode <= (rv_funct7[5]) ? OPCODE_SRA : OPCODE_SRL;
                            3'b110:  decoded_instruction.opcode <= OPCODE_OR;
                            3'b111:  decoded_instruction.opcode <= OPCODE_AND;
                            default: decoded_instruction.opcode <= OPCODE_ADD;
                        endcase
                    end
                    
                    RV32_OP_IMM: begin
                        decoded_instruction.instr_type <= INSTR_ALU;
                        decoded_instruction.immediate  <= {{20{if_id_opcode[31]}}, if_id_opcode[31:20]}; 
                        case (rv_funct3)
                            3'b000:  decoded_instruction.opcode <= OPCODE_ADDI; 
                            3'b001:  decoded_instruction.opcode <= OPCODE_SLLI;     
                            3'b010:  decoded_instruction.opcode <= OPCODE_COMPARE; 
                            3'b011:  decoded_instruction.opcode <= OPCODE_COMPARE; 
                            3'b100:  decoded_instruction.opcode <= OPCODE_XORI;     
                            3'b101:  decoded_instruction.opcode <= (rv_funct7[5]) ? OPCODE_SRAI : OPCODE_SRLI;
                            3'b110:  decoded_instruction.opcode <= OPCODE_ORI;     
                            3'b111:  decoded_instruction.opcode <= OPCODE_ANDI;     
                            default: decoded_instruction.opcode <= OPCODE_ADDI;
                        endcase
                    end
                    
                    RV32_LOAD: begin
                        decoded_instruction.instr_type       <= INSTR_LOAD;
                        decoded_instruction.opcode           <= OPCODE_LOAD;
                        decoded_instruction.immediate        <= {{20{if_id_opcode[31]}}, if_id_opcode[31:20]};
                    end 
                    
                    RV32_STORE: begin
                        decoded_instruction.instr_type        <= INSTR_STORE;
                        decoded_instruction.opcode            <= OPCODE_STORE;
                        decoded_instruction.operand2_reg      <= rv_rs2; 
                        decoded_instruction.result_reg        <= 5'd0; 
                        decoded_instruction.immediate         <= {{20{if_id_opcode[31]}}, if_id_opcode[31:25], if_id_opcode[11:7]};
                    end 
                    
                    RV32_BRANCH: begin
                        decoded_instruction.instr_type   <= INSTR_BRANCH;
                        decoded_instruction.operand2_reg <= rv_rs2; 
                        decoded_instruction.result_reg   <= 5'd0; 
                        decoded_instruction.immediate    <= {{20{if_id_opcode[31]}}, if_id_opcode[7], if_id_opcode[30:25], if_id_opcode[11:8], 1'b0};
                        case (rv_funct3)
                            3'b000:  decoded_instruction.opcode <= JE;
                            3'b001:  decoded_instruction.opcode <= JNE;
                            3'b100:  decoded_instruction.opcode <= JLT;
                            3'b101:  decoded_instruction.opcode <= JGE;
                            3'b110:  decoded_instruction.opcode <= JLTU;
                            3'b111:  decoded_instruction.opcode <= JGEU;
                            default: decoded_instruction.opcode <= JE;
                        endcase
                    end
                    
                    RV32_LUI: begin
                                 decoded_instruction.instr_type   <= INSTR_ALU; 
                                 decoded_instruction.opcode       <= OPCODE_ADDI; 
                                 decoded_instruction.operand1_reg <= 5'd0; 
                                 decoded_instruction.operand2_reg <= 5'd0; 
                                 decoded_instruction.result_reg   <= rv_rd;
                                 decoded_instruction.immediate    <= {if_id_opcode[31:12], 12'b0}; 
                    end

						  RV32_AUIPC: begin
								decoded_instruction.instr_type   <= INSTR_ALU; 
								decoded_instruction.opcode       <= OPCODE_ADDI;
								decoded_instruction.operand1_reg <= 5'd0; 
								decoded_instruction.operand2_reg <= 5'd0; 
								decoded_instruction.result_reg   <= rv_rd;
								decoded_instruction.immediate    <= {20'd0, if_id_pc, 2'b00} + {if_id_opcode[31:12], 12'b0}; 
						  end

                    RV32_JAL: begin
                        decoded_instruction.instr_type   <= INSTR_ALU; 
                        decoded_instruction.opcode       <= JAL;  
                        decoded_instruction.operand1_reg <= 5'd0; 
                        decoded_instruction.operand2_reg <= 5'd0; 
                        decoded_instruction.result_reg   <= rv_rd; 
                        decoded_instruction.immediate    <= {{12{if_id_opcode[31]}}, if_id_opcode[19:12], if_id_opcode[20], if_id_opcode[30:21], 1'b0};
                    end

                    RV32_JALR: begin
                        decoded_instruction.instr_type   <= INSTR_ALU; 
                        decoded_instruction.opcode       <= JALR; 
                        decoded_instruction.operand1_reg <= rv_rs1; 
                        decoded_instruction.operand2_reg <= 5'd0; 
                        decoded_instruction.result_reg   <= rv_rd; 
                        decoded_instruction.immediate    <= {{20{if_id_opcode[31]}}, if_id_opcode[31:20]};
                    end

                    default: begin
                        decoded_instruction.instr_type <= INSTR_OTHER;
                        decoded_instruction.opcode     <= 8'h00;
                        decoded_instruction.immediate  <= 32'b0;
                    end
                endcase
            end else begin
                id_valid <= 1'b0;
            end
        end
    end
endmodule
