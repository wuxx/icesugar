`ifndef RV32_CONTROL
`define RV32_CONTROL

`include "rv32_alu.sv"
`include "rv32_csrs.sv"
`include "rv32_branch.sv"
`include "rv32_imm.sv"
`include "rv32_mem.sv"
`include "rv32_opcodes.sv"

module rv32_control_unit (
    /* data in */
    input [31:0] instr_in,

    /* control in */
    input [4:0] rs1_in,
    input [4:0] rd_in,

    /* control out */
    output logic valid_out,
    output logic rs1_read_out,
    output logic rs2_read_out,
    output logic [2:0] imm_out,
    output logic [2:0] alu_op_out,
    output logic alu_sub_sra_out,
    output logic [1:0] alu_src1_out,
    output logic [1:0] alu_src2_out,
    output logic mem_read_out,
    output logic mem_write_out,
    output logic [1:0] mem_width_out,
    output logic mem_zero_extend_out,
    output logic mem_fence_out,
    output logic csr_read_out,
    output logic csr_write_out,
    output logic [1:0] csr_write_op_out,
    output logic csr_src_out,
    output logic [1:0] branch_op_out,
    output logic branch_pc_src_out,
    output logic ecall_out,
    output logic ebreak_out,
    output logic mret_out,
    output logic rd_write_out
);
    always_comb begin
        valid_out = 0;
        rs1_read_out = 0;
        rs2_read_out = 0;
        imm_out = 3'bx;
        alu_op_out = 3'bx;
        alu_sub_sra_out = 1'bx;
        alu_src1_out = 2'bx;
        alu_src2_out = 2'bx;
        mem_read_out = 0;
        mem_write_out = 0;
        mem_width_out = 2'bx;
        mem_zero_extend_out = 1'bx;
        mem_fence_out = 0;
        csr_read_out = 0;
        csr_write_out = 0;
        csr_write_op_out = 2'bx;
        csr_src_out = 1'bx;
        branch_op_out = `RV32_BRANCH_OP_NEVER;
        branch_pc_src_out = 1'bx;
        ecall_out = 0;
        ebreak_out = 0;
        mret_out = 0;
        rd_write_out = 0;

        casez (instr_in)
            `RV32_INSTR_LUI: begin
                valid_out = 1;
                imm_out = `RV32_IMM_U;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_ZERO;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_AUIPC: begin
                valid_out = 1;
                imm_out = `RV32_IMM_U;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_PC;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_JAL: begin
                valid_out = 1;
                imm_out = `RV32_IMM_J;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_PC;
                alu_src2_out = `RV32_ALU_SRC2_FOUR;
                branch_op_out = `RV32_BRANCH_OP_ALWAYS;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_JALR: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_PC;
                alu_src2_out = `RV32_ALU_SRC2_FOUR;
                branch_op_out = `RV32_BRANCH_OP_ALWAYS;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_BEQ: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_B;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                branch_op_out = `RV32_BRANCH_OP_ZERO;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_IMM;
            end
            `RV32_INSTR_BNE: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_B;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                branch_op_out = `RV32_BRANCH_OP_NON_ZERO;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_IMM;
            end
            `RV32_INSTR_BLT: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_B;
                alu_op_out = `RV32_ALU_OP_SLT;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                branch_op_out = `RV32_BRANCH_OP_NON_ZERO;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_IMM;
            end
            `RV32_INSTR_BGE: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_B;
                alu_op_out = `RV32_ALU_OP_SLT;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                branch_op_out = `RV32_BRANCH_OP_ZERO;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_IMM;
            end
            `RV32_INSTR_BLTU: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_B;
                alu_op_out = `RV32_ALU_OP_SLTU;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                branch_op_out = `RV32_BRANCH_OP_NON_ZERO;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_IMM;
            end
            `RV32_INSTR_BGEU: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_B;
                alu_op_out = `RV32_ALU_OP_SLTU;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                branch_op_out = `RV32_BRANCH_OP_ZERO;
                branch_pc_src_out = `RV32_BRANCH_PC_SRC_IMM;
            end
            `RV32_INSTR_LB: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_read_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_BYTE;
                mem_zero_extend_out = 0;
                rd_write_out = 1;
            end
            `RV32_INSTR_LH: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_read_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_HALF;
                mem_zero_extend_out = 0;
                rd_write_out = 1;
            end
            `RV32_INSTR_LW: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_read_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_WORD;
                rd_write_out = 1;
            end
            `RV32_INSTR_LBU: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_read_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_BYTE;
                mem_zero_extend_out = 1;
                rd_write_out = 1;
            end
            `RV32_INSTR_LHU: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_read_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_HALF;
                mem_zero_extend_out = 1;
                rd_write_out = 1;
            end
            `RV32_INSTR_SB: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_S;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_write_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_BYTE;
            end
            `RV32_INSTR_SH: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_S;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_write_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_HALF;
            end
            `RV32_INSTR_SW: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                imm_out = `RV32_IMM_S;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                mem_write_out = 1;
                mem_width_out = `RV32_MEM_WIDTH_WORD;
            end
            `RV32_INSTR_ADDI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_SLTI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_SLT;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_SLTIU: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_SLTU;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_XORI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_XOR;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_ORI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_OR;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_ANDI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_I;
                alu_op_out = `RV32_ALU_OP_AND;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_SLLI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_SHAMT;
                alu_op_out = `RV32_ALU_OP_SLL;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_SRLI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_SHAMT;
                alu_op_out = `RV32_ALU_OP_SRL_SRA;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_SRAI: begin
                valid_out = 1;
                rs1_read_out = 1;
                imm_out = `RV32_IMM_SHAMT;
                alu_op_out = `RV32_ALU_OP_SRL_SRA;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_ADD: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_SUB: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_ADD_SUB;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_SLL: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_SLL;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_SLT: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_SLT;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_SLTU: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_SLTU;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_XOR: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_XOR;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_SRL: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_SRL_SRA;
                alu_sub_sra_out = 0;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_SRA: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_SRL_SRA;
                alu_sub_sra_out = 1;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_OR: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_OR;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_AND: begin
                valid_out = 1;
                rs1_read_out = 1;
                rs2_read_out = 1;
                alu_op_out = `RV32_ALU_OP_AND;
                alu_src1_out = `RV32_ALU_SRC1_REG;
                alu_src2_out = `RV32_ALU_SRC2_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_FENCE: begin
                valid_out = 1;
            end
            `RV32_INSTR_FENCE_I: begin
                valid_out = 1;
                mem_fence_out = 1;
            end
            `RV32_INSTR_ECALL: begin
                valid_out = 1;
                ecall_out = 1;
            end
            `RV32_INSTR_EBREAK: begin
                valid_out = 1;
                ebreak_out = 1;
            end
            `RV32_INSTR_MRET: begin
                valid_out = 1;
                mret_out = 1;
            end
            `RV32_INSTR_WFI: begin
                valid_out = 1;
            end
            `RV32_INSTR_CSRRW: begin
                valid_out = 1;
                rs1_read_out = 1;
                csr_read_out = |rd_in;
                csr_write_out = 1;
                csr_write_op_out = `RV32_CSR_WRITE_OP_RW;
                csr_src_out = `RV32_CSR_SRC_REG;
                rd_write_out = |rd_in;
            end
            `RV32_INSTR_CSRRS: begin
                valid_out = 1;
                rs1_read_out = 1;
                csr_read_out = 1;
                csr_write_out = |rs1_in;
                csr_write_op_out = `RV32_CSR_WRITE_OP_RS;
                csr_src_out = `RV32_CSR_SRC_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_CSRRC: begin
                valid_out = 1;
                rs1_read_out = 1;
                csr_read_out = 1;
                csr_write_out = |rs1_in;
                csr_write_op_out = `RV32_CSR_WRITE_OP_RC;
                csr_src_out = `RV32_CSR_SRC_REG;
                rd_write_out = 1;
            end
            `RV32_INSTR_CSRRWI: begin
                valid_out = 1;
                imm_out = `RV32_IMM_ZIMM;
                csr_read_out = |rd_in;
                csr_write_out = 1;
                csr_write_op_out = `RV32_CSR_WRITE_OP_RW;
                csr_src_out = `RV32_CSR_SRC_IMM;
                rd_write_out = |rd_in;
            end
            `RV32_INSTR_CSRRSI: begin
                valid_out = 1;
                imm_out = `RV32_IMM_ZIMM;
                csr_read_out = 1;
                csr_write_out = |rs1_in;
                csr_write_op_out = `RV32_CSR_WRITE_OP_RS;
                csr_src_out = `RV32_CSR_SRC_IMM;
                rd_write_out = 1;
            end
            `RV32_INSTR_CSRRCI: begin
                valid_out = 1;
                imm_out = `RV32_IMM_ZIMM;
                csr_read_out = 1;
                csr_write_out = |rs1_in;
                csr_write_op_out = `RV32_CSR_WRITE_OP_RC;
                csr_src_out = `RV32_CSR_SRC_IMM;
                rd_write_out = 1;
            end
        endcase
    end
endmodule

`endif
