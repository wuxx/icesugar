// ============================================================================
//  uart_tx.v -- 8N1 串口发送器 (只发)
// ============================================================================
`default_nettype none

module uart_tx #(
    parameter CLK_HZ = 24_000_000,
    parameter BAUD  = 9600
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       ena,      // idle && ena 时开始发送一个字节
    output wire       idle,
    output reg        tx
);

    localparam integer BITC = CLK_HZ / BAUD;    // 24MHz/9600 = 2500
    localparam [2:0] S_IDLE = 0, S_START = 1, S_DATA = 2, S_STOP = 3;

    reg [2:0]  st;
    reg [15:0] cnt;
    reg [7:0]  sh;
    reg [3:0]  bitn;

    assign idle = (st == S_IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; cnt <= 0; sh <= 0; bitn <= 0; tx <= 1'b1;
        end else begin
            case (st)
            S_IDLE: begin
                tx  <= 1'b1;
                cnt <= 16'd0;
                if (ena) begin
                    sh <= data;
                    st <= S_START;
                end
            end
            S_START: begin
                tx <= 1'b0;                 // 起始位
                if (cnt >= BITC-1) begin
                    cnt  <= 16'd0;
                    tx   <= sh[0];          // 数据位 0
                    sh   <= {1'b0, sh[7:1]};
                    bitn <= 4'd1;
                    st   <= S_DATA;
                end else cnt <= cnt + 1'b1;
            end
            S_DATA: begin
                if (cnt >= BITC-1) begin
                    cnt <= 16'd0;
                    if (bitn == 4'd8) begin
                        tx <= 1'b1;         // 停止位
                        st <= S_STOP;
                    end else begin
                        tx   <= sh[0];
                        sh   <= {1'b0, sh[7:1]};
                        bitn <= bitn + 1'b1;
                    end
                end else cnt <= cnt + 1'b1;
            end
            S_STOP: begin
                tx <= 1'b1;
                if (cnt >= BITC-1) begin
                    cnt <= 16'd0;
                    st  <= S_IDLE;
                end else cnt <= cnt + 1'b1;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
