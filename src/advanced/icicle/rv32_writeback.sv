`ifndef RV32_WRITEBACK
`define RV32_WRITEBACK

module rv32_writeback (
    input clk,
    input reset,

`ifdef RISCV_FORMAL
    /* debug control in */
    input intr_in,
    input trap_in,
    input [4:0] rs1_in,
    input [4:0] rs2_in,
    input [3:0] mem_read_mask_in,
    input [3:0] mem_write_mask_in,

    /* debug data in */
    input [31:0] pc_in,
    input [31:0] next_pc_in,
    input [31:0] instr_in,
    input [31:0] rs1_value_in,
    input [31:0] rs2_value_in,
    input [31:0] mem_address_in,
    input [31:0] mem_read_value_in,
    input [31:0] mem_write_value_in,

    /* RISC-V formal interface */
    output logic rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic rvfi_trap,
    output logic rvfi_halt,
    output logic rvfi_intr,
    output logic [1:0] rvfi_mode,
    output logic [4:0] rvfi_rs1_addr,
    output logic [4:0] rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [4:0] rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [3:0] rvfi_mem_rmask,
    output logic [3:0] rvfi_mem_wmask,
    output logic [31:0] rvfi_mem_rdata,
    output logic [31:0] rvfi_mem_wdata,
`endif

    /* control in (from hazard) */
    input flush_in,

    /* control in */
    input valid_in,
    input [4:0] rd_in,
    input rd_write_in,

    /* data in */
    input [31:0] rd_value_in
);
`ifdef RISCV_FORMAL
    always_ff @(posedge clk) begin
        if (!flush_in && (valid_in || trap_in)) begin
            rvfi_valid <= 1;
            rvfi_order <= rvfi_order + 1;
            rvfi_insn <= instr_in;
            rvfi_trap <= trap_in;
            rvfi_halt <= 0;
            rvfi_intr <= intr_in;
            rvfi_mode <= 3;
            rvfi_rs1_addr <= rs1_in;
            rvfi_rs2_addr <= rs2_in;
            rvfi_rs1_rdata <= rs1_value_in;
            rvfi_rs2_rdata <= rs2_value_in;
            rvfi_rd_addr <= rd_write_in ? rd_in : 0;
            rvfi_rd_wdata <= rd_write_in && |rd_in ? rd_value_in : 0;
            rvfi_pc_rdata <= pc_in;
            rvfi_pc_wdata <= next_pc_in;
            rvfi_mem_addr <= mem_address_in;
            rvfi_mem_rmask <= mem_read_mask_in;
            rvfi_mem_wmask <= mem_write_mask_in;
            rvfi_mem_rdata <= mem_read_value_in;
            rvfi_mem_wdata <= mem_write_value_in;
        end else begin
            rvfi_valid <= 0;
        end
    end
`endif
endmodule

`endif
