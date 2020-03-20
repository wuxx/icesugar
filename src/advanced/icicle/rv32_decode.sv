`ifndef RV32_DECODE
`define RV32_DECODE

`include "rv32_control.sv"
`include "rv32_csrs.sv"
`include "rv32_regs.sv"

module rv32_decode (
    input clk,
    input reset,

`ifdef RISCV_FORMAL
    /* debug control in */
    input intr_in,

    /* debug data in */
    input [31:0] next_pc_in,

    /* debug control out */
    output logic intr_out,

    /* debug data out */
    output logic [31:0] next_pc_out,
    output logic [31:0] instr_out,
`endif

    /* control in (from hazard) */
    input stall_in,
    input flush_in,
    input writeback_flush_in,

    /* control in (from fetch) */
    input valid_in,
    input exception_in,
    input [3:0] exception_cause_in,
    input branch_predicted_taken_in,

    /* control in (from writeback) */
    input [4:0] rd_in,
    input rd_write_in,

    /* data in */
    input [31:0] pc_in,
    input [31:0] instr_in,

    /* data in (from writeback) */
    input [31:0] rd_value_in,

    /* control out (to hazard) */
    output logic [4:0] rs1_unreg_out,
    output logic rs1_read_unreg_out,
    output logic [4:0] rs2_unreg_out,
    output logic rs2_read_unreg_out,
    output logic mem_fence_unreg_out,

    /* control out */
    output logic branch_predicted_taken_out,
    output logic valid_out,
    output logic exception_out,
    output logic [3:0] exception_cause_out,
    output logic [4:0] rs1_out,
    output logic [4:0] rs2_out,
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
    output logic [4:0] rd_out,
    output logic rd_write_out,

    /* data out */
    output logic [31:0] pc_out,
    output logic [31:0] rs1_value_out,
    output logic [31:0] rs2_value_out,
    output logic [31:0] imm_value_out,
    output logic [11:0] csr_out
);
    logic [4:0] rs2;
    logic [4:0] rs1;
    logic [4:0] rd;

    assign rs2 = instr_in[24:20];
    assign rs1 = instr_in[19:15];
    assign rd  = instr_in[11:7];

    assign rs1_unreg_out = rs1;
    assign rs2_unreg_out = rs2;

    rv32_regs regs (
        .clk(clk),
        .stall_in(stall_in),
        .writeback_flush_in(writeback_flush_in),

        /* control in */
        .rs1_in(rs1),
        .rs2_in(rs2),
        .rd_in(rd_in),
        .rd_write_in(rd_write_in),

        /* data in */
        .rd_value_in(rd_value_in),

        /* data out */
        .rs1_value_out(rs1_value_out),
        .rs2_value_out(rs2_value_out)
    );

    logic valid;
    logic rs1_read;
    logic rs2_read;
    logic [2:0] imm;
    logic [2:0] alu_op;
    logic alu_sub_sra;
    logic [1:0] alu_src1;
    logic [1:0] alu_src2;
    logic mem_read;
    logic mem_write;
    logic [1:0] mem_width;
    logic mem_zero_extend;
    logic mem_fence;
    logic csr_read;
    logic csr_write;
    logic [1:0] csr_write_op;
    logic csr_src;
    logic [1:0] branch_op;
    logic branch_pc_src;
    logic ecall;
    logic ebreak;
    logic mret;
    logic rd_write;

    assign rs1_read_unreg_out = rs1_read;
    assign rs2_read_unreg_out = rs2_read;
    assign mem_fence_unreg_out = mem_fence;

    rv32_control_unit control_unit (
        /* data in */
        .instr_in(instr_in),

        /* control in */
        .rs1_in(rs1),
        .rd_in(rd),

        /* control out */
        .valid_out(valid),
        .rs1_read_out(rs1_read),
        .rs2_read_out(rs2_read),
        .imm_out(imm),
        .alu_op_out(alu_op),
        .alu_sub_sra_out(alu_sub_sra),
        .alu_src1_out(alu_src1),
        .alu_src2_out(alu_src2),
        .mem_read_out(mem_read),
        .mem_write_out(mem_write),
        .mem_width_out(mem_width),
        .mem_zero_extend_out(mem_zero_extend),
        .mem_fence_out(mem_fence),
        .csr_read_out(csr_read),
        .csr_write_out(csr_write),
        .csr_write_op_out(csr_write_op),
        .csr_src_out(csr_src),
        .branch_op_out(branch_op),
        .branch_pc_src_out(branch_pc_src),
        .ecall_out(ecall),
        .ebreak_out(ebreak),
        .mret_out(mret),
        .rd_write_out(rd_write)
    );

    logic [31:0] imm_value;

    rv32_imm_mux imm_mux (
        /* control in */
        .imm_in(imm),

        /* data in */
        .instr_in(instr_in),

        /* data out */
        .imm_value_out(imm_value)
    );

    logic [11:0] csr;

    assign csr = instr_in[31:20];

    always_ff @(posedge clk) begin
        if (!stall_in) begin
`ifdef RISCV_FORMAL
            intr_out <= intr_in;
            next_pc_out <= next_pc_in;
            instr_out <= instr_in;
`endif

            branch_predicted_taken_out <= branch_predicted_taken_in;
            valid_out <= valid_in && valid;
            if (!exception_in && valid_in && !valid) begin
                exception_out <= 1;
                exception_cause_out <= `RV32_MCAUSE_INSTR_ILLEGAL_EXCEPTION;
            end else begin
                exception_out <= exception_in;
                exception_cause_out <= exception_cause_in;
            end
            rs1_out <= rs1;
            rs2_out <= rs2;
            alu_op_out <= alu_op;
            alu_sub_sra_out <= alu_sub_sra;
            alu_src1_out <= alu_src1;
            alu_src2_out <= alu_src2;
            mem_read_out <= mem_read;
            mem_write_out <= mem_write;
            mem_width_out <= mem_width;
            mem_zero_extend_out <= mem_zero_extend;
            mem_fence_out <= mem_fence;
            csr_read_out <= csr_read;
            csr_write_out <= csr_write;
            csr_write_op_out <= csr_write_op;
            csr_src_out <= csr_src;
            branch_op_out <= branch_op;
            branch_pc_src_out <= branch_pc_src;
            ecall_out <= ecall;
            ebreak_out <= ebreak;
            mret_out <= mret;
            rd_out <= rd;
            rd_write_out <= rd_write;

            pc_out <= pc_in;
            imm_value_out <= imm_value;
            csr_out <= csr;

            if (flush_in) begin
                branch_predicted_taken_out <= 0;
                valid_out <= 0;
                exception_out <= 0;
                mem_read_out <= 0;
                mem_write_out <= 0;
                csr_read_out <= 0;
                csr_write_out <= 0;
                branch_op_out <= `RV32_BRANCH_OP_NEVER;
                ecall_out <= 0;
                ebreak_out <= 0;
                mret_out <= 0;
                rd_write_out <= 0;
            end
        end

        if (reset) begin
            branch_predicted_taken_out <= 0;
            valid_out <= 0;
            exception_out <= 0;
            rs1_out <= 0;
            rs2_out <= 0;
            alu_op_out <= 0;
            alu_sub_sra_out <= 0;
            alu_src1_out <= 0;
            alu_src2_out <= 0;
            mem_read_out <= 0;
            mem_write_out <= 0;
            mem_width_out <= 0;
            mem_zero_extend_out <= 0;
            mem_fence_out <= 0;
            csr_read_out <= 0;
            csr_write_out <= 0;
            csr_write_op_out <= 0;
            csr_src_out <= 0;
            branch_op_out <= 0;
            branch_pc_src_out <= 0;
            ecall_out <= 0;
            ebreak_out <= 0;
            mret_out <= 0;
            rd_out <= 0;
            rd_write_out <= 0;

            pc_out <= 0;
            imm_value_out <= 0;
            csr_out <= 0;
        end
    end
endmodule

`endif
