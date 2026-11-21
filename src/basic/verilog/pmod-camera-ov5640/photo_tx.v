// ============================================================================
//  photo_tx.v -- 把行缓冲里的像素打包成带 CRC 的行包, 用串口发出去
//
//  每行一个包:
//      A5 5A            magic (主机端靠它重新同步)
//      row_lo row_hi    行号 (小端, 16 位)
//      len_lo len_hi    本行数据长度 (小端, 16 位)
//      data[len]        原始 YUYV 字节 (640 像素 x 2 字节 = 1280)
//      crc_lo crc_hi    CRC16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
//
//  CRC 覆盖范围 = 行号(2) + 长度(2) + 本行数据字节, **不含 magic**。
//  主机端按同样的顺序算一遍就能校验:
//
//      payload = buf[2:6] + data        # buf[0:2] 是 A5 5A
//      crc16_ccitt_false(payload)
//
//  状态包 (row = 0xFFFF, len = 16):  格式和行包完全一样, 只是内容是
//  16 字节的诊断信息 (诊断码/flags/段号/已采行数/已采字节数...)。
//  正常发图像时也每段发一个, 这样主机端能实时看到 FPGA 在干什么。
//
//  丢字节会让 CRC 失败, 主机端跳过该包继续找 magic, 自动重新对齐。
// ============================================================================
`default_nettype none

module photo_tx #(
    parameter CLK_HZ = 24_000_000,
    parameter BAUD  = 460800,
    parameter LINEB = 1280,      // 每行字节数
    parameter KROWS = 8,         // 每段多少行
    parameter AW    = 14         // 行缓冲地址位宽
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        go,           // 脉冲: 开始发 (段包或状态包)
    input  wire        stat_ena,     // 1 = 发状态包, 0 = 发图像段包
    input  wire [127:0] stat_data,   // 状态包内容 (16 字节, 只用低 128 位)
    input  wire [8:0]  row0,         // 本段起始行号
    output reg         done,         // 脉冲: 发完

    // ---- 行缓冲读口 (与 dvp_linebuf 的 clk24 侧对接) ----
    output reg  [AW-1:0] rb_addr,
    output reg          rb_adv,
    input  wire [7:0]   rb_data,

    output wire         tx
);

    localparam [2:0] S_IDLE = 0, S_HDR = 1, S_DATA = 2, S_CRC = 3, S_END = 4;

    localparam [15:0]  LINEB16 = LINEB;
    localparam [10:0]  LINEB_M1 = LINEB - 1;
    localparam [AW-1:0] LINEB_A  = LINEB;
    localparam [15:0]  STAT_LEN = 16;
    localparam [10:0]  STAT_M1  = 16 - 1;

    reg [2:0]  st;
    reg [2:0]  hdr_idx;      // 0..5 (magic2 + row2 + len2)
    reg [10:0] data_idx;
    reg [3:0]  row_idx;      // 段内行号
    reg [15:0] cur_row;      // 当前行号
    reg [AW-1:0] row_off;    // 当前行在缓冲里的起始偏移 (行号 * LINEB)
    reg [15:0] len_field;    // 包头里的长度字段
    reg        crc_hi;       // CRC 低字节已发完
    reg        stat_mode;    // 1 = 发状态包

    // ------------------------------------------------------------------
    //  CRC16/CCITT-FALSE (逐位, 8 拍/字节; 串口 460800 下 60 拍/字节, 够用)
    // ------------------------------------------------------------------
    reg [15:0] crc;
    reg [3:0]  cbit;
    reg [7:0]  cbyte;
    reg        cbusy;
    reg        cstart;
    reg [7:0]  cbyte_in;

    wire        cfb    = crc[15] ^ cbyte[cbit-1];
    wire [15:0] cshift = {crc[14:0], 1'b0};
    wire [15:0] cnext  = cfb ? (cshift ^ 16'h1021) : cshift;

    // ------------------------------------------------------------------
    //  发送字节源 (全部用组合逻辑, 避免"寄存器比索引晚一拍"的老毛病)
    // ------------------------------------------------------------------
    wire       uart_idle;
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .data(tx_byte), .ena(tx_ena), .idle(uart_idle), .tx(tx)
    );

    wire       tx_ena = (st == S_HDR) || (st == S_DATA) || (st == S_CRC);
    wire       send_now = uart_idle && tx_ena;

    //  状态包的第 i 个字节 (data_idx 只有 0..15 会用到)
    wire [7:0] stat_byte = stat_data[{data_idx[3:0], 3'b000} +: 8];
    wire [7:0] data_byte = stat_mode ? stat_byte : rb_data;

    //  包头 6 字节: A5 5A | row_lo row_hi | len_lo len_hi
    wire [7:0] hdr_byte = (hdr_idx == 3'd0) ? 8'hA5 :
                          (hdr_idx == 3'd1) ? 8'h5A :
                          (hdr_idx == 3'd2) ? cur_row[7:0] :
                          (hdr_idx == 3'd3) ? cur_row[15:8] :
                          (hdr_idx == 3'd4) ? len_field[7:0] :
                                              len_field[15:8];
    wire [7:0] crc_byte = crc_hi ? crc[15:8] : crc[7:0];

    wire [7:0] tx_byte = (st == S_HDR) ? hdr_byte :
                         (st == S_DATA) ? data_byte :
                         (st == S_CRC) ? crc_byte : 8'h00;

    wire       last_data = stat_mode ? (data_idx == STAT_M1)
                                     : (data_idx == LINEB_M1);

    //  magic 不进 CRC; row/len/data 进 CRC
    wire       hdr_in_crc = (hdr_idx >= 3'd2);

    always @(posedge clk) begin
        if (!rst_n) begin
            st       <= S_IDLE;
            hdr_idx  <= 3'd0;
            data_idx <= 11'd0;
            row_idx  <= 4'd0;
            cur_row  <= 16'd0;
            row_off  <= {AW{1'b0}};
            len_field<= LINEB16;
            stat_mode<= 1'b0;
            crc      <= 16'hFFFF;
            crc_hi   <= 1'b0;
            cbit     <= 4'd0;
            cbyte    <= 8'd0;
            cbusy    <= 1'b0;
            cstart   <= 1'b0;
            cbyte_in <= 8'd0;
            rb_addr  <= {AW{1'b0}};
            rb_adv   <= 1'b0;
            done     <= 1'b0;
        end else begin
            done   <= 1'b0;
            cstart <= 1'b0;
            rb_adv <= 1'b0;

            // ---------------- CRC 引擎 ----------------
            if (cstart) begin
                cbyte <= cbyte_in;
                cbit  <= 4'd8;
                cbusy <= 1'b1;
            end else if (cbusy) begin
                crc  <= cnext;
                cbit <= cbit - 4'd1;
                if (cbit == 4'd1) cbusy <= 1'b0;
            end

            // ---------------- 行缓冲读指针 ----------------
            //  rb_data 是同步读 (1 拍延迟): rb_data(N) = mem[rb_addr(N-1)]。
            //  所以第 n 个发出的数据字节 = mem[row_off + n]:
            //    - 本行最后一个包头字节发出的那一拍, 先把 rb_addr 装成 row_off;
            //    - 之后每发一个数据字节推进 1;
            //    - 串口一个字节要 243 拍 (115200), 远大于 1 拍的读延迟,
            //      所以第一个数据字节发出时 rb_data 已经是 mem[row_off] 了。
            if (st == S_HDR && hdr_idx == 3'd5 && send_now) begin
                rb_addr <= row_off;
            end else if (st == S_DATA && send_now && !stat_mode) begin
                rb_adv  <= 1'b1;
                rb_addr <= rb_addr + 1'b1;
            end

            // ---------------- 发送状态机 ----------------
            case (st)
            //-----------------------------------------------------------
            S_IDLE: begin
                if (go) begin
                    stat_mode <= stat_ena;
                    row_idx   <= 4'd0;
                    if (stat_ena) begin
                        cur_row   <= 16'hFFFF;      // 0xFFFF = 状态包
                        len_field <= STAT_LEN;
                        row_off   <= {AW{1'b0}};
                    end else begin
                        cur_row   <= {7'd0, row0};
                        len_field <= LINEB16;
                        row_off   <= {AW{1'b0}};
                    end
                    crc     <= 16'hFFFF;      // CRC 从包头开始算
                    crc_hi  <= 1'b0;
                    hdr_idx <= 3'd0;
                    st      <= S_HDR;
                end
            end
            //-----------------------------------------------------------
            S_HDR: begin
                if (send_now) begin
                    if (hdr_in_crc) begin
                        cstart   <= 1'b1;     // row/len 进 CRC
                        cbyte_in <= hdr_byte;
                    end
                    if (hdr_idx == 3'd5) begin
                        data_idx <= 11'd0;
                        crc_hi   <= 1'b0;
                        st       <= S_DATA;
                    end else begin
                        hdr_idx <= hdr_idx + 3'd1;
                    end
                end
            end
            //-----------------------------------------------------------
            S_DATA: begin
                if (send_now) begin
                    cstart   <= 1'b1;
                    cbyte_in <= data_byte;
                    if (last_data) begin
                        st <= S_CRC;
                    end else begin
                        data_idx <= data_idx + 11'd1;
                    end
                end
            end
            //-----------------------------------------------------------
            S_CRC: begin
                //  等 CRC 算完再发, 否则会发到半成品
                if (!cbusy && send_now) begin
                    if (!crc_hi) begin
                        crc_hi <= 1'b1;         // 下一个发高字节
                    end else begin
                        crc_hi <= 1'b0;
                        if (stat_mode) begin
                            st <= S_END;         // 状态包只有一行
                        end else if (row_idx == KROWS-1) begin
                            st <= S_END;
                        end else begin
                            row_idx <= row_idx + 4'd1;
                            cur_row <= cur_row + 16'd1;
                            row_off <= row_off + LINEB_A;   // 下一行在缓冲里 +1280
                            hdr_idx <= 3'd0;
                            //  **每行都要把 CRC 复位** —— CRC 只覆盖"本行"的
                            //  行号+长度+数据, 不能接着上一行的余数继续算。
                            //  (踩过: 只在 go 时初始化, 同一段第 2~8 行全部 CRC 错)
                            crc     <= 16'hFFFF;
                            st      <= S_HDR;
                        end
                    end
                end
            end
            //-----------------------------------------------------------
            S_END: begin
                done <= 1'b1;
                st   <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
