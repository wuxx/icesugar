module rvfi_wrapper (
    input clock,
    input reset,

    `RVFI_OUTPUTS
);
    /* instruction memory bus */
    (* keep *) logic [31:0] instr_address;
    (* keep *) logic instr_read;
    (* keep *) logic [31:0] instr_read_value;
    (* keep *) logic instr_ready;
    (* keep *) logic instr_fault;

    /* data memory bus */
    (* keep *) logic [31:0] data_address;
    (* keep *) logic data_read;
    (* keep *) logic data_write;
    (* keep *) logic [31:0] data_read_value;
    (* keep *) logic [3:0] data_write_mask;
    (* keep *) logic [31:0] data_write_value;
    (* keep *) logic data_ready;
    (* keep *) logic data_fault;

    /* timer */
    (* keep *) logic [63:0] cycle;

    rv32 uut (
        .clk(clock),
        .reset(reset),

        `RVFI_CONN,

        /* instruction memory bus */
        .instr_address_out(instr_address),
        .instr_read_out(instr_read),
        .instr_read_value_in(instr_read_value),
        .instr_ready_in(instr_ready),
        .instr_fault_in(instr_fault),

        /* data memory bus */
        .data_address_out(data_address),
        .data_read_out(data_read),
        .data_write_out(data_write),
        .data_read_value_in(data_read_value),
        .data_write_mask_out(data_write_mask),
        .data_write_value_out(data_write_value),
        .data_ready_in(data_ready),
        .data_fault_in(data_fault),

        /* timer */
        .cycle_out(cycle)
    );

    assign data_fault = !`RISCV_FORMAL_VALIDADDR(data_address);
endmodule
