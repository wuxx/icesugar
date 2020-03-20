`ifndef RV32
`define RV32

`include "rv32_decode.sv"
`include "rv32_execute.sv"
`include "rv32_fetch.sv"
`include "rv32_hazard.sv"
`include "rv32_mem.sv"
`include "rv32_writeback.sv"

module rv32 #(
    parameter RESET_VECTOR = 32'b0,
    parameter BYPASSING = 0,
    parameter BRANCH_PREDICTION = 0
) (
    input clk,
    input reset,

`ifdef RISCV_FORMAL
    `RVFI_OUTPUTS,
`endif

    /* instruction memory bus */
    output logic [31:0] instr_address_out,
    output logic instr_read_out,
    input [31:0] instr_read_value_in,
    input instr_ready_in,
    input instr_fault_in,

    /* data memory bus */
    output logic [31:0] data_address_out,
    output logic data_read_out,
    output logic data_write_out,
    input [31:0] data_read_value_in,
    output logic [3:0] data_write_mask_out,
    output logic [31:0] data_write_value_out,
    input data_ready_in,
    input data_fault_in,

    /* timer */
    output logic [63:0] cycle_out
);
    /* hazard -> fetch control */
    logic pcgen_stall;
    logic fetch_stall;
    logic fetch_flush;

    /* hazard -> decode control */
    logic decode_stall;
    logic decode_flush;

    /* hazard -> execute control */
    logic execute_stall;
    logic execute_flush;

    /* hazard -> mem control */
    logic mem_stall;
    logic mem_flush;

    /* hazard -> writeback control */
    logic writeback_flush;

`ifdef RISCV_FORMAL
    /* fetch -> decode debug control */
    logic fetch_intr;

    /* fetch -> decode debug data */
    logic [31:0] fetch_next_pc;
`endif

    /* fetch -> hazard */
    logic fetch_overwrite_pc;

    /* fetch -> decode control */
    logic fetch_valid;
    logic fetch_exception;
    logic [3:0] fetch_exception_cause;
    logic fetch_branch_predicted_taken;

    /* fetch -> decode data */
    logic [31:0] fetch_pc;
    logic [31:0] fetch_instr;

    /* decode -> hazard control */
    logic [4:0] decode_rs1_unreg;
    logic decode_rs1_read_unreg;
    logic [4:0] decode_rs2_unreg;
    logic decode_rs2_read_unreg;
    logic decode_mem_fence_unreg;

`ifdef RISCV_FORMAL
    /* decode -> execute debug control */
    logic decode_intr;

    /* decode -> execute debug data */
    logic [31:0] decode_next_pc;
    logic [31:0] decode_instr;
`endif

    /* decode -> execute control */
    logic decode_branch_predicted_taken;
    logic decode_valid;
    logic decode_exception;
    logic [3:0] decode_exception_cause;
    logic [4:0] decode_rs1;
    logic [4:0] decode_rs2;
    logic [2:0] decode_alu_op;
    logic decode_alu_sub_sra;
    logic [1:0] decode_alu_src1;
    logic [1:0] decode_alu_src2;
    logic decode_mem_read;
    logic decode_mem_write;
    logic [1:0] decode_mem_width;
    logic decode_mem_zero_extend;
    logic decode_mem_fence;
    logic decode_csr_read;
    logic decode_csr_write;
    logic [1:0] decode_csr_write_op;
    logic decode_csr_src;
    logic [1:0] decode_branch_op;
    logic decode_branch_pc_src;
    logic decode_ecall;
    logic decode_ebreak;
    logic decode_mret;
    logic [4:0] decode_rd;
    logic decode_rd_write;

    /* decode -> execute data */
    logic [31:0] decode_pc;
    logic [31:0] decode_rs1_value;
    logic [31:0] decode_rs2_value;
    logic [31:0] decode_imm_value;
    logic [11:0] decode_csr;

`ifdef RISCV_FORMAL
    /* execute -> mem debug control */
    logic execute_intr;
    logic [4:0] execute_rs1;
    logic [4:0] execute_rs2;

    /* execute -> mem debug data */
    logic [31:0] execute_next_pc;
    logic [31:0] execute_instr;
`endif

    /* execute -> mem control */
    logic execute_branch_predicted_taken;
    logic execute_branch_misaligned;
    logic execute_valid;
    logic execute_exception;
    logic [3:0] execute_exception_cause;
    logic execute_mem_read;
    logic execute_mem_write;
    logic [1:0] execute_mem_width;
    logic execute_mem_zero_extend;
    logic execute_mem_fence;
    logic execute_csr_read;
    logic execute_csr_write;
    logic [1:0] execute_csr_write_op;
    logic execute_csr_src;
    logic [1:0] execute_branch_op;
    logic execute_ecall;
    logic execute_ebreak;
    logic execute_mret;
    logic [4:0] execute_rd;
    logic execute_rd_write;

    /* execute -> mem data */
    logic [31:0] execute_pc;
    logic [31:0] execute_result;
    logic [31:0] execute_rs1_value;
    logic [31:0] execute_rs2_value;
    logic [31:0] execute_imm_value;
    logic [11:0] execute_csr;
    logic [31:0] execute_branch_pc;

`ifdef RISCV_FORMAL
    /* mem -> writeback debug control */
    logic mem_intr;
    logic mem_trap;
    logic [4:0] mem_rs1;
    logic [4:0] mem_rs2;
    logic [3:0] mem_read_mask;
    logic [3:0] mem_write_mask;

    /* mem -> writeback debug data */
    logic [31:0] mem_pc;
    logic [31:0] mem_next_pc;
    logic [31:0] mem_instr;
    logic [31:0] mem_rs1_value;
    logic [31:0] mem_rs2_value;
    logic [31:0] mem_address;
    logic [31:0] mem_read_value;
    logic [31:0] mem_write_value;
`endif

    /* mem -> writeback control */
    logic mem_valid;
    logic [4:0] mem_rd;
    logic mem_rd_write;

    /* mem -> fetch control */
    logic mem_trap_unreg;
    logic mem_branch_mispredicted;

    /* mem -> writeback data */
    logic [31:0] mem_rd_value;

    /* mem -> fetch data */
    logic [31:0] mem_trap_pc;
    logic [31:0] mem_branch_pc;

    rv32_hazard_unit #(
        .BYPASSING(BYPASSING)
    ) hazard_unit (
        /* control in */
        .decode_rs1_unreg_in(decode_rs1_unreg),
        .decode_rs1_read_unreg_in(decode_rs1_read_unreg),
        .decode_rs2_unreg_in(decode_rs2_unreg),
        .decode_rs2_read_unreg_in(decode_rs2_read_unreg),
        .decode_mem_fence_unreg_in(decode_mem_fence_unreg),

        .decode_mem_read_in(decode_mem_read),
        .decode_mem_fence_in(decode_mem_fence),
        .decode_csr_read_in(decode_csr_read),
        .decode_rd_in(decode_rd),
        .decode_rd_write_in(decode_rd_write),

        .fetch_overwrite_pc_in(fetch_overwrite_pc),

        .execute_rd_in(execute_rd),
        .execute_mem_fence_in(execute_mem_fence),

        .mem_rd_in(mem_rd),
        .mem_trap_in(mem_trap_unreg),
        .mem_branch_mispredicted_in(mem_branch_mispredicted),

        .instr_read_in(instr_read_out),
        .instr_ready_in(instr_ready_in),

        .data_read_in(data_read_out),
        .data_write_in(data_write_out),
        .data_ready_in(data_ready_in),

        /* control out */
        .pcgen_stall_out(pcgen_stall),

        .fetch_stall_out(fetch_stall),
        .fetch_flush_out(fetch_flush),

        .decode_stall_out(decode_stall),
        .decode_flush_out(decode_flush),

        .execute_stall_out(execute_stall),
        .execute_flush_out(execute_flush),

        .mem_stall_out(mem_stall),
        .mem_flush_out(mem_flush),

        .writeback_flush_out(writeback_flush)
    );

    rv32_fetch #(
        .RESET_VECTOR(RESET_VECTOR),
        .BRANCH_PREDICTION(BRANCH_PREDICTION)
    ) fetch (
        .clk(clk),
        .reset(reset),

`ifdef RISCV_FORMAL
        /* debug control out */
        .intr_out(fetch_intr),

        /* debug data out */
        .next_pc_out(fetch_next_pc),
`endif

        /* control in (from hazard) */
        .pcgen_stall_in(pcgen_stall),
        .stall_in(fetch_stall),
        .flush_in(fetch_flush),

        /* control in (from mem) */
        .trap_in(mem_trap_unreg),
        .branch_mispredicted_in(mem_branch_mispredicted),

        /* control in (from memory bus) */
        .instr_fault_in(instr_fault_in),

        /* control out (to hazard) */
        .overwrite_pc_out(fetch_overwrite_pc),

        /* control out (to memory bus) */
        .instr_read_out(instr_read_out),

        /* control out */
        .valid_out(fetch_valid),
        .exception_out(fetch_exception),
        .exception_cause_out(fetch_exception_cause),
        .branch_predicted_taken_out(fetch_branch_predicted_taken),

        /* data in (from mem) */
        .trap_pc_in(mem_trap_pc),
        .branch_pc_in(mem_branch_pc),

        /* data in (from memory bus) */
        .instr_read_value_in(instr_read_value_in),

        /* data out */
        .pc_out(fetch_pc),
        .instr_out(fetch_instr),

        /* data out (to memory bus) */
        .instr_address_out(instr_address_out)
    );

    rv32_decode decode (
        .clk(clk),
        .reset(reset),

`ifdef RISCV_FORMAL
        /* debug control in */
        .intr_in(fetch_intr),

        /* debug data in */
        .next_pc_in(fetch_next_pc),

        /* debug data out */
        .intr_out(decode_intr),
        .next_pc_out(decode_next_pc),
        .instr_out(decode_instr),
`endif

        /* control in (from hazard) */
        .stall_in(decode_stall),
        .flush_in(decode_flush),
        .writeback_flush_in(writeback_flush),

        /* control in (from fetch) */
        .valid_in(fetch_valid),
        .exception_in(fetch_exception),
        .exception_cause_in(fetch_exception_cause),
        .branch_predicted_taken_in(fetch_branch_predicted_taken),

        /* control in (from writeback) */
        .rd_in(mem_rd),
        .rd_write_in(mem_rd_write),

        /* data in */
        .pc_in(fetch_pc),
        .instr_in(fetch_instr),

        /* data in (from writeback) */
        .rd_value_in(mem_rd_value),

        /* control out (to hazard) */
        .rs1_unreg_out(decode_rs1_unreg),
        .rs1_read_unreg_out(decode_rs1_read_unreg),
        .rs2_unreg_out(decode_rs2_unreg),
        .rs2_read_unreg_out(decode_rs2_read_unreg),
        .mem_fence_unreg_out(decode_mem_fence_unreg),

        /* control out */
        .branch_predicted_taken_out(decode_branch_predicted_taken),
        .valid_out(decode_valid),
        .exception_out(decode_exception),
        .exception_cause_out(decode_exception_cause),
        .rs1_out(decode_rs1),
        .rs2_out(decode_rs2),
        .alu_op_out(decode_alu_op),
        .alu_sub_sra_out(decode_alu_sub_sra),
        .alu_src1_out(decode_alu_src1),
        .alu_src2_out(decode_alu_src2),
        .mem_read_out(decode_mem_read),
        .mem_write_out(decode_mem_write),
        .mem_width_out(decode_mem_width),
        .mem_zero_extend_out(decode_mem_zero_extend),
        .mem_fence_out(decode_mem_fence),
        .csr_read_out(decode_csr_read),
        .csr_write_out(decode_csr_write),
        .csr_write_op_out(decode_csr_write_op),
        .csr_src_out(decode_csr_src),
        .branch_op_out(decode_branch_op),
        .branch_pc_src_out(decode_branch_pc_src),
        .ecall_out(decode_ecall),
        .ebreak_out(decode_ebreak),
        .mret_out(decode_mret),
        .rd_out(decode_rd),
        .rd_write_out(decode_rd_write),

        /* data out */
        .pc_out(decode_pc),
        .rs1_value_out(decode_rs1_value),
        .rs2_value_out(decode_rs2_value),
        .imm_value_out(decode_imm_value),
        .csr_out(decode_csr)
    );

    rv32_execute #(
        .BYPASSING(BYPASSING)
    ) execute (
        .clk(clk),
        .reset(reset),

`ifdef RISCV_FORMAL
        /* debug control in */
        .intr_in(decode_intr),

        /* debug data in */
        .next_pc_in(decode_next_pc),
        .instr_in(decode_instr),

        /* debug control out */
        .intr_out(execute_intr),
        .rs1_out(execute_rs1),
        .rs2_out(execute_rs2),

        /* debug data out */
        .next_pc_out(execute_next_pc),
        .instr_out(execute_instr),
`endif

        /* control in (from hazard) */
        .stall_in(execute_stall),
        .flush_in(execute_flush),
        .mem_flush_in(mem_flush),
        .writeback_flush_in(writeback_flush),

        /* control in */
        .branch_predicted_taken_in(decode_branch_predicted_taken),
        .valid_in(decode_valid),
        .exception_in(decode_exception),
        .exception_cause_in(decode_exception_cause),
        .rs1_in(decode_rs1),
        .rs2_in(decode_rs2),
        .alu_op_in(decode_alu_op),
        .alu_sub_sra_in(decode_alu_sub_sra),
        .alu_src1_in(decode_alu_src1),
        .alu_src2_in(decode_alu_src2),
        .mem_read_in(decode_mem_read),
        .mem_write_in(decode_mem_write),
        .mem_width_in(decode_mem_width),
        .mem_zero_extend_in(decode_mem_zero_extend),
        .mem_fence_in(decode_mem_fence),
        .csr_read_in(decode_csr_read),
        .csr_write_in(decode_csr_write),
        .csr_write_op_in(decode_csr_write_op),
        .csr_src_in(decode_csr_src),
        .branch_op_in(decode_branch_op),
        .branch_pc_src_in(decode_branch_pc_src),
        .ecall_in(decode_ecall),
        .ebreak_in(decode_ebreak),
        .mret_in(decode_mret),
        .rd_in(decode_rd),
        .rd_write_in(decode_rd_write),

        /* control in (from writeback) */
        .writeback_rd_in(mem_rd),
        .writeback_rd_write_in(mem_rd_write),

        /* data in */
        .pc_in(decode_pc),
        .rs1_value_in(decode_rs1_value),
        .rs2_value_in(decode_rs2_value),
        .imm_value_in(decode_imm_value),
        .csr_in(decode_csr),

        /* data in (from writeback) */
        .writeback_rd_value_in(mem_rd_value),

        /* control out */
        .branch_predicted_taken_out(execute_branch_predicted_taken),
        .branch_misaligned_out(execute_branch_misaligned),
        .valid_out(execute_valid),
        .exception_out(execute_exception),
        .exception_cause_out(execute_exception_cause),
        .mem_read_out(execute_mem_read),
        .mem_write_out(execute_mem_write),
        .mem_width_out(execute_mem_width),
        .mem_zero_extend_out(execute_mem_zero_extend),
        .mem_fence_out(execute_mem_fence),
        .csr_read_out(execute_csr_read),
        .csr_write_out(execute_csr_write),
        .csr_write_op_out(execute_csr_write_op),
        .csr_src_out(execute_csr_src),
        .branch_op_out(execute_branch_op),
        .ecall_out(execute_ecall),
        .ebreak_out(execute_ebreak),
        .mret_out(execute_mret),
        .rd_out(execute_rd),
        .rd_write_out(execute_rd_write),

        /* data out */
        .pc_out(execute_pc),
        .result_out(execute_result),
        .rs1_value_out(execute_rs1_value),
        .rs2_value_out(execute_rs2_value),
        .imm_value_out(execute_imm_value),
        .csr_out(execute_csr),
        .branch_pc_out(execute_branch_pc)
    );

    rv32_mem mem (
        .clk(clk),
        .reset(reset),

`ifdef RISCV_FORMAL
        /* debug control in */
        .intr_in(execute_intr),
        .rs1_in(execute_rs1),
        .rs2_in(execute_rs2),

        /* debug data in */
        .next_pc_in(execute_next_pc),
        .instr_in(execute_instr),

        /* debug control out */
        .intr_out(mem_intr),
        .trap_out(mem_trap),
        .rs1_out(mem_rs1),
        .rs2_out(mem_rs2),
        .read_mask_out(mem_read_mask),
        .write_mask_out(mem_write_mask),

        /* debug data out */
        .pc_out(mem_pc),
        .next_pc_out(mem_next_pc),
        .instr_out(mem_instr),
        .rs1_value_out(mem_rs1_value),
        .rs2_value_out(mem_rs2_value),
        .address_out(mem_address),
        .read_value_out(mem_read_value),
        .write_value_out(mem_write_value),
`endif

        /* control in (from hazard) */
        .stall_in(mem_stall),
        .flush_in(mem_flush),
        .writeback_flush_in(writeback_flush),

        /* control in */
        .branch_predicted_taken_in(execute_branch_predicted_taken),
        .branch_misaligned_in(execute_branch_misaligned),
        .valid_in(execute_valid),
        .exception_in(execute_exception),
        .exception_cause_in(execute_exception_cause),
        .read_in(execute_mem_read),
        .write_in(execute_mem_write),
        .width_in(execute_mem_width),
        .zero_extend_in(execute_mem_zero_extend),
        .csr_read_in(execute_csr_read),
        .csr_write_in(execute_csr_write),
        .csr_write_op_in(execute_csr_write_op),
        .csr_src_in(execute_csr_src),
        .branch_op_in(execute_branch_op),
        .ecall_in(execute_ecall),
        .ebreak_in(execute_ebreak),
        .mret_in(execute_mret),
        .rd_in(execute_rd),
        .rd_write_in(execute_rd_write),

        /* control in (from memory bus) */
        .data_fault_in(data_fault_in),

        /* data in */
        .pc_in(execute_pc),
        .result_in(execute_result),
        .rs1_value_in(execute_rs1_value),
        .rs2_value_in(execute_rs2_value),
        .imm_value_in(execute_imm_value),
        .csr_in(execute_csr),
        .branch_pc_in(execute_branch_pc),

        /* data in (from memory bus) */
        .data_read_value_in(data_read_value_in),

        /* control out */
        .valid_out(mem_valid),
        .trap_unreg_out(mem_trap_unreg),
        .branch_mispredicted_out(mem_branch_mispredicted),
        .rd_out(mem_rd),
        .rd_write_out(mem_rd_write),

        /* control out (to memory bus) */
        .data_read_out(data_read_out),
        .data_write_out(data_write_out),
        .data_write_mask_out(data_write_mask_out),

        /* data out */
        .rd_value_out(mem_rd_value),
        .trap_pc_out(mem_trap_pc),
        .branch_pc_out(mem_branch_pc),

        /* data out (to memory bus) */
        .data_address_out(data_address_out),
        .data_write_value_out(data_write_value_out),

        /* data out (to timer) */
        .cycle_out(cycle_out)
    );

    rv32_writeback writeback (
        .clk(clk),
        .reset(reset),

`ifdef RISCV_FORMAL
        `RVFI_CONN,

        .intr_in(mem_intr),
        .trap_in(mem_trap),
        .rs1_in(mem_rs1),
        .rs2_in(mem_rs2),
        .mem_read_mask_in(mem_read_mask),
        .mem_write_mask_in(mem_write_mask),
        .pc_in(mem_pc),
        .next_pc_in(mem_next_pc),
        .instr_in(mem_instr),
        .rs1_value_in(mem_rs1_value),
        .rs2_value_in(mem_rs2_value),
        .mem_address_in(mem_address),
        .mem_read_value_in(mem_read_value),
        .mem_write_value_in(mem_write_value),
`endif

        /* control in (from hazard) */
        .flush_in(writeback_flush),

        /* control in */
        .valid_in(mem_valid),
        .rd_in(mem_rd),
        .rd_write_in(mem_rd_write),

        /* data in */
        .rd_value_in(mem_rd_value)
    );
endmodule

`endif
