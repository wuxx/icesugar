// ============================================================================
//  uart_printer.v -- 文本报表输出器
//
//  文本模板放在 text.hex (每行 1 字节), 其中可以嵌入转义序列:
//
//     0x00            结束
//     0x01 <idx>      插入 vars[idx] , 2 位十六进制
//     0x02 <idx>      插入 vars[idx] , 十进制
//     0x03 <idx>      插入 vars[idx] , 8 位十六进制
//     0x04 <idx>      vars[idx] != 0 -> "OK"  否则 -> "FAIL"
//     0x05 <idx>      插入 samples[idx] , 2 位十六进制
//
//  vars 是一个 32bit 变量的平铺总线, samples 是 8 个原始采样字节。
// ============================================================================
`default_nettype none

module uart_printer #(
    parameter CLK_HZ = 24_000_000,
    parameter BAUD  = 9600,
    parameter NVARS = 24
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    output reg                  busy,
    output reg                  done,
    input  wire [NVARS*32-1:0] vars_flat,
    input  wire [127:0]         samples,
    output wire                 tx
);

    // ------------------------------------------------------------------
    //  串口发送器
    // ------------------------------------------------------------------
    wire       uart_idle;
    reg  [7:0] e_byte;
    wire       e_ena = (st == S_EMIT);

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .data(e_byte), .ena(e_ena), .idle(uart_idle), .tx(tx)
    );

    // ------------------------------------------------------------------
    //  文本 ROM (2048 字节; 模板当前 1349 字节, ROM 太小的话
    //  tpos 会回绕, 终止符 0x00 永远读不到, 报表就会从头无限重复)
    // ------------------------------------------------------------------
    reg [7:0] trom [0:2047];
    initial $readmemh("text.hex", trom);

    reg [10:0] tpos;
    reg [7:0] tb;                 // 预取寄存器

    always @(posedge clk) tb <= trom[tpos];

    // ------------------------------------------------------------------
    //  状态
    // ------------------------------------------------------------------
    localparam [3:0] S_IDLE  = 0,  S_FETCH = 1,  S_NEXT  = 2,  S_ESCW  = 3,
                     S_ESC   = 4,  S_EMIT  = 5,  S_EDONE = 6,  S_DEC1  = 7,
                     S_DEC2  = 8,  S_DEC3  = 9,  S_DEC4  = 10, S_FIN   = 11;

    localparam [2:0] M_LIT = 0, M_HEX8 = 1, M_HEX32 = 2, M_DEC = 3,
                     M_OK = 4, M_SAMPLE = 5;

    reg [3:0]  st;
    reg [7:0]  esc;              // 转义类型
    reg [7:0]  esc_idx;          // 转义参数 (变量/采样序号)
    reg [2:0]  emit_mode;
    reg [3:0]  emit_cnt;
    reg [3:0]  emit_idx;
    reg [31:0] emit_val;
    reg [31:0] hex32_sr;      // hex32 输出用的移位寄存器(每发一个 nibble 左移 4 位)

    // ------------------------------------------------------------------
    //  十进制转换 (二进制长除法, 每次除法 32 拍)
    // ------------------------------------------------------------------
    reg [31:0] dec_val;          // 原始值
    reg [31:0] dec_cur;          // 当前被除数
    reg [31:0] dec_sh;
    reg [31:0] dec_quo;
    reg [4:0]  dec_rem;
    reg [5:0]  dec_bit;
    reg [3:0]  dec_dcnt;
    reg [3:0]  dec_dig [0:9];

    wire [4:0] rem_next  = {dec_rem[3:0], dec_sh[31]};
    wire       quot_bit  = (rem_next >= 5'd10);
    wire [4:0] rem_after = quot_bit ? (rem_next - 5'd10) : rem_next;

    integer k;
    reg [3:0] dec_start;
    reg [3:0] dec_start_r;    // dec_start 的寄存版本(放在关键路径外, 见 M_DEC)
    always @* begin
        dec_start = 4'd0;
        for (k = 1; k <= 9; k = k + 1)
            if (dec_dig[k] != 0) dec_start = k[3:0];
    end
    wire dec_is_zero = (dec_val == 0);

    // ------------------------------------------------------------------
    //  取值
    // ------------------------------------------------------------------
    // 注意: S_ESC 拍里 esc_idx 还没生效, 必须直接用 tb(=参数) 来索引
    //  注意: 索引要留 6 位, 否则 v32 以上的报表变量取不到
    //        (之前用 5 位时 dec(34) 实际读的是 v2, 数字对不上就是这个原因)
    wire [31:0] var_val = vars_flat[{tb[5:0], 5'b00000} +: 32];
    wire [7:0]  smp_val = samples[{tb[3:0], 3'b000} +: 8];

    function [7:0] hexnib(input [3:0] n);
        case (n)
            4'h0: hexnib = "0";  4'h1: hexnib = "1";
            4'h2: hexnib = "2";  4'h3: hexnib = "3";
            4'h4: hexnib = "4";  4'h5: hexnib = "5";
            4'h6: hexnib = "6";  4'h7: hexnib = "7";
            4'h8: hexnib = "8";  4'h9: hexnib = "9";
            4'ha: hexnib = "A";  4'hb: hexnib = "B";
            4'hc: hexnib = "C";  4'hd: hexnib = "D";
            4'he: hexnib = "E";  default: hexnib = "F";
        endcase
    endfunction

    wire ev_nz = (emit_val != 0);

    always @* begin
        case (emit_mode)
            M_LIT:    e_byte = emit_val[7:0];
            M_HEX8:   e_byte = emit_idx[0] ? hexnib(emit_val[3:0])
                                           : hexnib(emit_val[7:4]);
            M_HEX32:  e_byte = hexnib(hex32_sr[31:28]);
            M_OK:     case (emit_idx)
                          0:    e_byte = ev_nz ? "O" : "F";
                          1:    e_byte = ev_nz ? "K" : "A";
                          2:    e_byte = ev_nz ? " " : "I";
                          default: e_byte = ev_nz ? " " : "L";
                      endcase
            M_DEC:    if (emit_idx == 4'd0 && dec_is_zero) e_byte = "0";
                      else e_byte = dec_dig[dec_start_r - emit_idx] + 8'h30;
            default:  e_byte = emit_val[7:0];
        endcase
    end

    // ------------------------------------------------------------------
    //  主状态机
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; busy <= 1'b0; done <= 1'b0;
            tpos <= 11'd0; esc <= 0; esc_idx <= 0;
            emit_mode <= M_LIT; emit_cnt <= 0; emit_idx <= 0; emit_val <= 0;
            hex32_sr <= 0; dec_start_r <= 0;
            dec_val <= 0; dec_cur <= 0; dec_sh <= 0; dec_quo <= 0;
            dec_rem <= 0; dec_bit <= 0; dec_dcnt <= 0;
        end else begin
            done <= 1'b0;
            case (st)
            //-----------------------------------------------------------
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    st   <= S_FETCH;
                end
            end
            //-----------------------------------------------------------
            S_FETCH: begin
                if (tb == 8'h00) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    st   <= S_FIN;
                end else if ((tb >= 8'h01) && (tb <= 8'h05)) begin
                    esc  <= tb;
                    tpos <= tpos + 1'b1;
                    st   <= S_ESCW;
                end else begin
                    if (uart_idle) begin
                        emit_val  <= {24'd0, tb};
                        emit_mode <= M_LIT;
                        emit_cnt  <= 4'd1;
                        emit_idx  <= 4'd0;
                        tpos      <= tpos + 1'b1;
                        st        <= S_EMIT;
                    end
                end
            end
            //-----------------------------------------------------------
            S_ESCW:  st <= S_ESC;          // 等预取到参数字节
            //-----------------------------------------------------------
            S_ESC: begin
                esc_idx <= tb;
                tpos    <= tpos + 1'b1;
                case (esc)
                    8'h01: begin                      // hex8
                        emit_val  <= var_val;
                        emit_mode <= M_HEX8;
                        emit_cnt  <= 4'd2;
                        emit_idx  <= 4'd0;
                        st        <= S_EMIT;
                    end
                    8'h02: begin                      // decimal
                        dec_val <= var_val;
                        st      <= S_DEC1;
                    end
                    8'h03: begin                      // hex32
                        emit_val  <= var_val;
                        hex32_sr  <= var_val;        // 从最高 nibble 开始, 每次左移 4 位
                        emit_mode <= M_HEX32;
                        emit_cnt  <= 4'd8;
                        emit_idx  <= 4'd0;
                        st        <= S_EMIT;
                    end
                    8'h04: begin                      // OK / FAIL
                        emit_val  <= var_val;
                        emit_mode <= M_OK;
                        emit_cnt  <= (var_val != 0) ? 4'd2 : 4'd4;
                        emit_idx  <= 4'd0;
                        st        <= S_EMIT;
                    end
                    8'h05: begin                      // 采样字节 hex8
                        emit_val  <= {24'd0, smp_val};
                        emit_mode <= M_HEX8;
                        emit_cnt  <= 4'd2;
                        emit_idx  <= 4'd0;
                        st        <= S_EMIT;
                    end
                    default: st <= S_FETCH;
                endcase
            end
            //-----------------------------------------------------------
            S_EMIT: begin
                if (uart_idle) begin
                    if (emit_idx + 1'b1 >= emit_cnt) begin
                        emit_idx <= 4'd0;
                        st       <= S_EDONE;
                    end else begin
                        emit_idx <= emit_idx + 1'b1;
                        hex32_sr <= hex32_sr << 4;   // 下一个 nibble
                    end
                end
            end
            S_EDONE: st <= S_FETCH;
            //-----------------------------------------------------------
            S_DEC1: begin
                dec_cur  <= dec_val;
                dec_dcnt <= 4'd0;
                st       <= S_DEC2;
            end
            S_DEC2: begin
                dec_sh  <= dec_cur;
                dec_quo <= 32'd0;
                dec_rem <= 5'd0;
                dec_bit <= 6'd0;
                st      <= S_DEC3;
            end
            S_DEC3: begin
                dec_sh   <= {dec_sh[30:0], 1'b0};
                dec_rem  <= rem_after;
                dec_quo  <= {dec_quo[30:0], quot_bit};
                dec_bit  <= dec_bit + 1'b1;
                if (dec_bit == 6'd31) begin
                    dec_dig[dec_dcnt] <= rem_after;
                    dec_dcnt          <= dec_dcnt + 1'b1;
                    dec_cur           <= {dec_quo[30:0], quot_bit};
                    if (dec_dcnt == 4'd9) st <= S_DEC4;
                    else                 st <= S_DEC2;
                end
            end
            S_DEC4: begin
                emit_val  <= dec_val;
                emit_mode <= M_DEC;
                // dec_start = 最高的非零位序号 -> 一共要打印 dec_start+1 位
                // 输出顺序: 最高位 -> 个位, 即 dec_dig[dec_start] ... dec_dig[0]
                // emit_idx 从 0 开始计数, 实际取的是 dec_dig[dec_start-emit_idx]
                // dec_start 优先编码链有 4 级 LUT, 放在发射路径上会超时,
                // 所以在这里先寄存在 dec_start_r 里, 发射时只用寄存器值。
                dec_start_r <= dec_start;
                emit_cnt  <= dec_is_zero ? 4'd1 : (dec_start + 4'd1);
                emit_idx  <= 4'd0;
                st        <= S_EMIT;
            end
            //-----------------------------------------------------------
            S_FIN: st <= S_IDLE;
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
