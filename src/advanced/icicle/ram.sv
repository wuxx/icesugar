`ifndef RAM
`define RAM

module ram #(
    parameter SIZE = 2048
) (
    input clk,
    input reset,

    /* memory bus */
    input [31:0] address_in,
    input sel_in,
    output logic [31:0] read_value_out,
    input [3:0] write_mask_in,
    input [31:0] write_value_in,
    output logic ready_out
);
    logic [31:0] mem [SIZE-1:0];
    logic [31:0] read_value;
    logic ready;

`ifndef SPI_FLASH
`ifdef ICE40
    initial
        $readmemh("progmem_syn.hex", mem);
`elsif ECP5
    initial
        $readmemh("progmem.hex", mem);
`endif
`endif

    assign read_value_out = sel_in ? read_value : 0;
    assign ready_out = sel_in ? ready : 0;

    always_ff @(posedge clk) begin
        read_value <= {mem[address_in[31:2]][7:0], mem[address_in[31:2]][15:8], mem[address_in[31:2]][23:16], mem[address_in[31:2]][31:24]};

        if (sel_in && !reset) begin
            ready <= !ready;

            if (write_mask_in[3])
                mem[address_in[31:2]][7:0] <= write_value_in[31:24];

            if (write_mask_in[2])
                mem[address_in[31:2]][15:8] <= write_value_in[23:16];

            if (write_mask_in[1])
                mem[address_in[31:2]][23:16] <= write_value_in[15:8];

            if (write_mask_in[0])
                mem[address_in[31:2]][31:24] <= write_value_in[7:0];
        end else begin
            ready <= 0;
        end
    end
endmodule

`endif
