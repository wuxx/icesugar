`ifndef RV32_BRANCH
`define RV32_BRANCH

`define RV32_BRANCH_OP_NEVER    2'b00
`define RV32_BRANCH_OP_ZERO     2'b01
`define RV32_BRANCH_OP_NON_ZERO 2'b10
`define RV32_BRANCH_OP_ALWAYS   2'b11

`define RV32_BRANCH_PC_SRC_IMM 1'b0
`define RV32_BRANCH_PC_SRC_REG 1'b1

module rv32_branch_pc_mux (
    /* control in */
    input predicted_taken_in,
    input pc_src_in,

    /* data in */
    input [31:0] pc_in,
    input [31:0] rs1_value_in,
    input [31:0] imm_value_in,

    /* control out */
    output logic misaligned_out,

    /* data out */
    output logic [31:0] pc_out
);
    logic [31:0] taken_pc;
    logic [31:0] not_taken_pc;
    logic [31:0] pc;

    assign taken_pc = (pc_src_in ? rs1_value_in : pc_in) + imm_value_in;
    assign not_taken_pc = pc_in + 32'd4;

    assign pc = predicted_taken_in ? not_taken_pc : taken_pc;
    assign pc_out = {pc[31:1], 1'b0};

    assign misaligned_out = taken_pc[1] != 0;
endmodule

module rv32_branch_unit (
    /* control in */
    input predicted_taken_in,
    input [1:0] op_in,

    /* data in */
    input [31:0] result_in,

    /* control out */
    output logic taken_out,
    output logic mispredicted_out
);
    logic alu_non_zero;

    always_comb begin
        alu_non_zero = |result_in;

        case (op_in)
            `RV32_BRANCH_OP_NEVER:    taken_out = 0;
            `RV32_BRANCH_OP_ZERO:     taken_out = ~alu_non_zero;
            `RV32_BRANCH_OP_NON_ZERO: taken_out = alu_non_zero;
            `RV32_BRANCH_OP_ALWAYS:   taken_out = 1;
        endcase

        mispredicted_out = taken_out != predicted_taken_in;
    end
endmodule

`endif
