module music(clk, speaker);
input clk;
output speaker;
parameter clkdivider = 100000000/440/2;

reg [16:0] counter;
always @(posedge clk) if(counter==0) counter <= clkdivider-1; else counter <= counter-1;

reg speaker;
always @(posedge clk) if(counter==0) speaker <= ~speaker;
endmodule
