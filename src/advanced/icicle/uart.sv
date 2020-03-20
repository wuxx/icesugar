`ifndef UART
`define UART

`define UART_REG_CLK_DIV 2'b00
`define UART_REG_STATUS  2'b01
`define UART_REG_DATA    2'b10

module uart (
    input clk,
    input reset,

    /* serial port */
    input rx_in,
    output logic tx_out,

    /* memory bus */
    input [31:0] address_in,
    input sel_in,
    input read_in,
    output logic [31:0] read_value_out,
    input [3:0] write_mask_in,
    input [31:0] write_value_in,
    output logic ready_out
);
    logic [15:0] clk_div;

    logic [15:0] rx_clks;
    logic [3:0] rx_bits;
    logic [7:0] rx_buf;

    logic [7:0] rx_read_buf;
    logic rx_read_ready;

    logic [15:0] tx_clks;
    logic [3:0] tx_bits;
    logic [9:0] tx_buf;

    logic tx_write_ready;

    initial
        tx_buf[0] = 1;

    assign tx_out = tx_buf[0];
    assign tx_write_ready = ~|tx_bits;
    assign ready_out = sel_in;

    always_comb begin
        if (sel_in) begin
            case (address_in[3:2])
                `UART_REG_CLK_DIV: begin
                    read_value_out = {16'b0, clk_div};
                end
                `UART_REG_STATUS: begin
                    read_value_out = {30'b0, rx_read_ready, tx_write_ready};
                end
                `UART_REG_DATA: begin
                    read_value_out = {{24{~rx_read_ready}}, rx_read_ready ? rx_read_buf : 8'b0};
                end
                default: begin
                    read_value_out = 32'bx;
                end
            endcase
        end else begin
            read_value_out = 0;
        end
    end

    always_ff @(posedge clk) begin
        if (sel_in) begin
            case (address_in[3:2])
                `UART_REG_CLK_DIV: begin
                    if (write_mask_in[1])
                        clk_div[15:8] <= write_value_in[15:8];

                    if (write_mask_in[0])
                        clk_div[7:0] <= write_value_in[7:0];
                end
                `UART_REG_DATA: begin
                    if (read_in)
                        rx_read_ready <= 0;

                    if (write_mask_in[0] && !tx_bits) begin
                        tx_clks <= clk_div;
                        tx_bits <= 10;
                        tx_buf <= {1'b1, write_value_in[7:0], 1'b0};
                    end
                end
            endcase
        end

        if (rx_bits) begin
            if (rx_clks) begin
                rx_clks <= rx_clks - 1;
            end else begin
                rx_clks <= clk_div;
                rx_bits <= rx_bits - 1;

                case (rx_bits)
                    10: begin
                        if (rx_in)
                            rx_bits <= 0;
                    end
                    1: begin
                        if (rx_in) begin
                            rx_read_ready <= 1;
                            rx_read_buf <= rx_buf;
                        end
                    end
                    default: begin
                        rx_buf <= {rx_in, rx_buf[7:1]};
                    end
                endcase
            end
        end else if (!rx_in) begin
            rx_clks <= clk_div[15:1];
            rx_bits <= 10;
        end

        if (tx_bits) begin
            if (tx_clks) begin
                tx_clks <= tx_clks - 1;
            end else begin
                tx_clks <= clk_div;
                tx_bits <= tx_bits - 1;
                tx_buf <= {1'b1, tx_buf[9:1]};
            end
        end

        if (reset) begin
            rx_bits <= 0;

            tx_bits <= 0;
            tx_buf[0] <= 1;
        end
    end
endmodule

`endif
