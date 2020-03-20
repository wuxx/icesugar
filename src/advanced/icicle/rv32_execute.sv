`ifndef RV32_EXECUTE
`define RV32_EXECUTE

`include "rv32_alu.sv"
`include "rv32_branch.sv"

module rv32_execute #(
    parameter BYPASSING = 0
) (
    input clk,
    input reset,

`ifdef RISCV_FORMAL
    /* debug control in */
    input intr_in,

    /* debug data in */
    input [31:0] next_pc_in,
    input [31:0] instr_in,

    /* debug control out */
    output logic intr_out,
    output logic [4:0] rs1_out,
    output logic [4:0] rs2_out,

    /* debug data out */
    output logic [31:0] next_pc_out,
    output logic [31:0] instr_out,
`endif

    /* control in (from hazard) */
    input stall_in,
    input flush_in,
    input mem_flush_in,
    input writeback_flush_in,

    /* control in */
    input branch_predicted_taken_in,
    input valid_in,
    input exception_in,
    input [3:0] exception_cause_in,
    input [4:0] rs1_in,
    input [4:0] rs2_in,
    input [2:0] alu_op_in,
    input alu_sub_sra_in,
    input [1:0] alu_src1_in,
    input [1:0] alu_src2_in,
    input mem_read_in,
    input mem_write_in,
    input [1:0] mem_width_in,
    input mem_zero_extend_in,
    input mem_fence_in,
    input csr_read_in,
    input csr_write_in,
    input [1:0] csr_write_op_in,
    input csr_src_in,
    input [1:0] branch_op_in,
    input branch_pc_src_in,
    input ecall_in,
    input ebreak_in,
    input mret_in,
    input [4:0] rd_in,
    input rd_write_in,

    /* control in (from writeback) */
    input [4:0] writeback_rd_in,
    input writeback_rd_write_in,

    /* data in */
    input [31:0] pc_in,
    input [31:0] rs1_value_in,
    input [31:0] rs2_value_in,
    input [31:0] imm_value_in,
    input [11:0] csr_in,

    /* data in (from writeback) */
    input [31:0] writeback_rd_value_in,

    /* control out */
    output logic branch_predicted_taken_out,
    output logic branch_misaligned_out,
    output logic valid_out,
    output logic exception_out,
    output logic [3:0] exception_cause_out,
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
    output logic ecall_out,
    output logic ebreak_out,
    output logic mret_out,
    output logic [4:0] rd_out,
    output logic rd_write_out,

    /* data out */
    output logic [31:0] pc_out,
    output logic [31:0] result_out,
    output logic [31:0] rs1_value_out,
    output logic [31:0] rs2_value_out,
    output logic [31:0] imm_value_out,
    output logic [11:0] csr_out,
    output logic [31:0] branch_pc_out
);
    /* bypassing */
    logic [31:0] rs1_value;
    logic [31:0] rs2_value;

    generate
        if (BYPASSING) begin
            always_comb begin
                if (rd_write_out && !mem_flush_in && rd_out == rs1_in && |rs1_in)
                    rs1_value = result_out;
                else if (writeback_rd_write_in && !writeback_flush_in && writeback_rd_in == rs1_in && |rs1_in)
                    rs1_value = writeback_rd_value_in;
                else
                    rs1_value = rs1_value_in;

                if (rd_write_out && !mem_flush_in && rd_out == rs2_in && |rs2_in)
                    rs2_value = result_out;
                else if (writeback_rd_write_in && !writeback_flush_in && writeback_rd_in == rs2_in && |rs2_in)
                    rs2_value = writeback_rd_value_in;
                else
                    rs2_value = rs2_value_in;
            end
        end else begin
            assign rs1_value = rs1_value_in;
            assign rs2_value = rs2_value_in;
        end
    endgenerate

    /* ALU */
    logic [31:0] alu_result;

    rv32_alu alu (
        /* control in */
        .op_in(alu_op_in),
        .sub_sra_in(alu_sub_sra_in),
        .src1_in(alu_src1_in),
        .src2_in(alu_src2_in),

        /* data in */
        .pc_in(pc_in),
        .rs1_value_in(rs1_value),
        .rs2_value_in(rs2_value),
        .imm_value_in(imm_value_in),

        /* data out */
        .result_out(alu_result)
    );

    /* branch target calculation */
    logic branch_misaligned;
    logic [31:0] branch_pc;

    rv32_branch_pc_mux branch_pc_mux (
        /* control in */
        .predicted_taken_in(branch_predicted_taken_in),
        .pc_src_in(branch_pc_src_in),

        /* data in */
        .pc_in(pc_in),
        .rs1_value_in(rs1_value),
        .imm_value_in(imm_value_in),

        /* control out */
        .misaligned_out(branch_misaligned),

        /* data out */
        .pc_out(branch_pc)
    );

    always_ff @(posedge clk) begin
        if (!stall_in) begin
`ifdef RISCV_FORMAL
            intr_out <= intr_in;
            next_pc_out <= next_pc_in;
            rs1_out <= rs1_in;
            rs2_out <= rs2_in;
            instr_out <= instr_in;
`endif

            branch_predicted_taken_out <= branch_predicted_taken_in;
            branch_misaligned_out <= branch_misaligned;
            valid_out <= valid_in;
            exception_out <= exception_in;
            exception_cause_out <= exception_cause_in;
            mem_read_out <= mem_read_in;
            mem_write_out <= mem_write_in;
            mem_width_out <= mem_width_in;
            mem_zero_extend_out <= mem_zero_extend_in;
            mem_fence_out <= mem_fence_in;
            csr_read_out <= csr_read_in;
            csr_write_out <= csr_write_in;
            csr_write_op_out <= csr_write_op_in;
            csr_src_out <= csr_src_in;
            branch_op_out <= branch_op_in;
            ecall_out <= ecall_in;
            ebreak_out <= ebreak_in;
            mret_out <= mret_in;
            rd_out <= rd_in;
            rd_write_out <= rd_write_in;
            pc_out <= pc_in;
            rs1_value_out <= rs1_value;
            rs2_value_out <= rs2_value;
            imm_value_out <= imm_value_in;
            csr_out <= csr_in;
            branch_pc_out <= branch_pc;
            result_out <= alu_result;

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
            mem_read_out <= 0;
            mem_write_out <= 0;
            mem_width_out <= 0;
            mem_zero_extend_out <= 0;
            mem_fence_out <= 0;
            csr_read_out <= 0;
            csr_write_out <= 0;
            branch_op_out <= 0;
            ecall_out <= 0;
            ebreak_out <= 0;
            mret_out <= 0;
            rd_out <= 0;
            rd_write_out <= 0;
            rs2_value_out <= 0;
            branch_pc_out <= 0;
            result_out <= 0;
        end
    end
endmodule

`endif
