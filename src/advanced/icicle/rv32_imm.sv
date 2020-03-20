`ifndef RV32_IMM
`define RV32_IMM

`define RV32_IMM_I     3'b000
`define RV32_IMM_S     3'b001
`define RV32_IMM_B     3'b010
`define RV32_IMM_U     3'b011
`define RV32_IMM_J     3'b100
`define RV32_IMM_SHAMT 3'b101
`define RV32_IMM_ZIMM  3'b110

module rv32_imm_mux (
    /* control in */
    input [2:0] imm_in,

    /* data in */
    input [31:0] instr_in,

    /* data out */
    output logic [31:0] imm_value_out
);
    logic sign;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    logic [31:0] shamt;
    logic [31:0] zimm;

    assign sign = instr_in[31];

    assign imm_i = {{21{sign}}, instr_in[30:25], instr_in[24:21], instr_in[20]};
    assign imm_s = {{21{sign}}, instr_in[30:25], instr_in[11:8],  instr_in[7]};
    assign imm_b = {{20{sign}}, instr_in[7],     instr_in[30:25], instr_in[11:8],  1'b0};
    assign imm_u = {sign,       instr_in[30:20], instr_in[19:12], 12'b0};
    assign imm_j = {{12{sign}}, instr_in[19:12], instr_in[20],    instr_in[30:25], instr_in[24:21], 1'b0};

    assign shamt = {27'bx, instr_in[24:20]};
    assign zimm  = {27'b0, instr_in[19:15]};

    always_comb begin
        case (imm_in)
            `RV32_IMM_I:     imm_value_out = imm_i;
            `RV32_IMM_S:     imm_value_out = imm_s;
            `RV32_IMM_B:     imm_value_out = imm_b;
            `RV32_IMM_U:     imm_value_out = imm_u;
            `RV32_IMM_J:     imm_value_out = imm_j;
            `RV32_IMM_SHAMT: imm_value_out = shamt;
            `RV32_IMM_ZIMM:  imm_value_out = zimm;
            default:         imm_value_out = 32'bx;
        endcase
    end
endmodule

`endif
