`ifndef RV32_HAZARD
`define RV32_HAZARD

module rv32_hazard_unit #(
    parameter BYPASSING = 0
) (
    /* control in */
    input [4:0] decode_rs1_unreg_in,
    input decode_rs1_read_unreg_in,
    input [4:0] decode_rs2_unreg_in,
    input decode_rs2_read_unreg_in,
    input decode_mem_fence_unreg_in,

    input decode_mem_read_in,
    input decode_mem_fence_in,
    input decode_csr_read_in,
    input [4:0] decode_rd_in,
    input decode_rd_write_in,

    input fetch_overwrite_pc_in,

    input [4:0] execute_rd_in,
    input execute_mem_fence_in,

    input [4:0] mem_rd_in,
    input mem_trap_in,
    input mem_branch_mispredicted_in,

    input instr_read_in,
    input instr_ready_in,

    input data_read_in,
    input data_write_in,
    input data_ready_in,

    /* control out */
    output logic pcgen_stall_out,

    output logic fetch_stall_out,
    output logic fetch_flush_out,

    output logic decode_stall_out,
    output logic decode_flush_out,

    output logic execute_stall_out,
    output logic execute_flush_out,

    output logic mem_stall_out,
    output logic mem_flush_out,

    output logic writeback_flush_out
);
    logic rs1_matches;
    logic rs2_matches;
    logic pcgen_wait_for_bus;
    logic fetch_wait_for_rd_write;
    logic fetch_wait_for_mem_fence;
    logic execute_wait_for_bus;

    generate
        if (BYPASSING) begin
            assign rs1_matches = decode_rs1_unreg_in == decode_rd_in && decode_rs1_read_unreg_in;
            assign rs2_matches = decode_rs2_unreg_in == decode_rd_in && decode_rs2_read_unreg_in;
            assign fetch_wait_for_rd_write = (rs1_matches || rs2_matches) && |decode_rd_in && (decode_mem_read_in || decode_csr_read_in) && decode_rd_write_in;
        end else begin
            assign rs1_matches = (decode_rs1_unreg_in == decode_rd_in || decode_rs1_unreg_in == execute_rd_in || decode_rs1_unreg_in == mem_rd_in) && decode_rs1_read_unreg_in;
            assign rs2_matches = (decode_rs2_unreg_in == decode_rd_in || decode_rs2_unreg_in == execute_rd_in || decode_rs2_unreg_in == mem_rd_in) && decode_rs2_read_unreg_in;
            assign fetch_wait_for_rd_write = (rs1_matches || rs2_matches) && |decode_rd_in && decode_rd_write_in;
        end
    endgenerate

    assign pcgen_wait_for_bus = instr_read_in && !instr_ready_in;
    assign fetch_wait_for_mem_fence = decode_mem_fence_unreg_in || decode_mem_fence_in || execute_mem_fence_in;
    assign execute_wait_for_bus = (data_read_in || data_write_in) && !data_ready_in;

    assign pcgen_stall_out = fetch_stall_out || pcgen_wait_for_bus;

    assign fetch_stall_out = decode_stall_out || fetch_wait_for_rd_write || fetch_wait_for_mem_fence;
    assign fetch_flush_out = pcgen_stall_out || mem_trap_in || mem_branch_mispredicted_in || fetch_overwrite_pc_in;

    assign decode_stall_out = execute_stall_out;
    assign decode_flush_out = fetch_stall_out || mem_trap_in || mem_branch_mispredicted_in || fetch_overwrite_pc_in;

    assign execute_stall_out = mem_stall_out || execute_wait_for_bus;
    assign execute_flush_out = decode_stall_out || mem_trap_in || mem_branch_mispredicted_in || fetch_overwrite_pc_in;

    assign mem_stall_out = 0;
    assign mem_flush_out = execute_stall_out;

    assign writeback_flush_out = mem_stall_out;
endmodule

`endif
