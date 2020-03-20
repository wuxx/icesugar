`ifndef RV32_FETCH
`define RV32_FETCH

`include "rv32_csrs.sv"
`include "rv32_opcodes.sv"

module rv32_fetch #(
    parameter RESET_VECTOR = 32'b0,
    parameter BRANCH_PREDICTION = 0
) (
    input clk,
    input reset,

`ifdef RISCV_FORMAL
    /* debug control out */
    output logic intr_out,

    /* debug data out */
    output logic [31:0] next_pc_out,
`endif

    /* control in (from hazard) */
    input pcgen_stall_in,
    input stall_in,
    input flush_in,

    /* control in (from mem) */
    input trap_in,
    input branch_mispredicted_in,

    /* control in (from memory bus) */
    input instr_fault_in,

    /* data in (from mem) */
    input [31:0] trap_pc_in,
    input [31:0] branch_pc_in,

    /* data in (from memory bus) */
    input [31:0] instr_read_value_in,

    /* control out (to hazard) */
    output logic overwrite_pc_out,

    /* control out (to memory bus) */
    output logic instr_read_out,

    /* control out */
    output logic valid_out,
    output logic exception_out,
    output logic [3:0] exception_cause_out,
    output logic branch_predicted_taken_out,

    /* data out */
    output logic [31:0] pc_out,
    output logic [31:0] instr_out,

    /* data out (to memory bus) */
    output logic [31:0] instr_address_out
);
    logic [31:0] pc;
    logic [31:0] next_pc;

    logic overwrite_pc;
    logic trap;
    logic [31:0] overwritten_pc;

    logic sign;
    logic [31:0] imm_j;
    logic [31:0] imm_b;
    logic [6:0] opcode;

    logic branch_predicted_taken;
    logic [31:0] branch_offset;

    assign overwrite_pc_out = overwrite_pc;

    assign instr_read_out = 1;
    assign instr_address_out = pc;

    assign sign = instr_read_value_in[31];
    assign imm_j = {{12{sign}}, instr_read_value_in[19:12], instr_read_value_in[20],    instr_read_value_in[30:25], instr_read_value_in[24:21], 1'b0};
    assign imm_b = {{20{sign}}, instr_read_value_in[7],     instr_read_value_in[30:25], instr_read_value_in[11:8],  1'b0};
    assign opcode = instr_read_value_in[6:0];

    generate
        if (BRANCH_PREDICTION) begin
            always_comb begin
                casez ({opcode, sign})
                    {`RV32_OPCODE_JAL, 1'b?}: begin
                        branch_predicted_taken = 1;
                        branch_offset = imm_j;
                    end
                    {`RV32_OPCODE_BRANCH, 1'b1}: begin
                        branch_predicted_taken = 1;
                        branch_offset = imm_b;
                    end
                    default: begin
                        branch_predicted_taken = 0;
                        branch_offset = 32'd4;
                    end
                endcase
            end
        end else begin
            assign branch_predicted_taken = 0;
            assign branch_offset = 32'd4;
        end
    endgenerate

    always_comb begin
        if (overwrite_pc)
            next_pc = overwritten_pc;
        else if (trap_in)
            next_pc = trap_pc_in;
        else if (branch_mispredicted_in)
            next_pc = branch_pc_in;
        else
            next_pc = pc + branch_offset;
    end

    initial begin
        pc <= RESET_VECTOR;
        instr_out <= `RV32_INSTR_NOP;
    end

    always_ff @(posedge clk) begin
        if (pcgen_stall_in) begin
            if (!overwrite_pc && (trap_in || branch_mispredicted_in)) begin
                overwrite_pc <= 1;
                trap <= trap_in;
                overwritten_pc <= trap_in ? trap_pc_in : branch_pc_in;
            end
        end else begin
            overwrite_pc <= 0;
            trap <= 0;
            pc <= next_pc;
        end

        if (!stall_in) begin
            valid_out <= 1;
            exception_out <= 0;
            branch_predicted_taken_out <= branch_predicted_taken;
            instr_out <= instr_read_value_in;
            pc_out <= pc;
`ifdef RISCV_FORMAL
            intr_out <= trap || trap_in;
            next_pc_out <= next_pc;
`endif

            if (instr_fault_in) begin
                valid_out <= 0;
                exception_out <= 1;
                exception_cause_out <= `RV32_MCAUSE_INSTR_FAULT_EXCEPTION;
                branch_predicted_taken_out <= 0;
`ifdef RISCV_FORMAL
                instr_out <= 0;
`else
                instr_out <= `RV32_INSTR_NOP;
`endif
            end

            if (flush_in) begin
                valid_out <= 0;
                exception_out <= 0;
                branch_predicted_taken_out <= 0;
                instr_out <= `RV32_INSTR_NOP;
                pc_out <= 0;
            end
        end

        if (reset) begin
            overwrite_pc <= 0;
            valid_out <= 0;
            exception_out <= 0;
            branch_predicted_taken_out <= 0;
            instr_out <= `RV32_INSTR_NOP;
            pc <= RESET_VECTOR;
            pc_out <= 0;
        end
    end
endmodule

`endif
