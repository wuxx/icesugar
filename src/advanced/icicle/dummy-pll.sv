module pll (
    input clock_in,
    output logic clock_out,
    output logic locked
);
    assign clock_out = clock_in;
    assign locked = 1;
endmodule
