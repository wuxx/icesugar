//this should be transformed into a bram when doing a synthesis in yosys 0.8
//and it should be equivalent to the explicit_bram.v

module implicit_bram(input wire clk, input wire rd_en, input wire wr_en, input wire [7:0] rd_addr, input wire [7:0] wr_addr, input wire [15:0] data_in, output reg [15:0] data_out, output reg valid_out);

   reg [15:0] memory [0:255];
   integer i;

   initial begin
      for(i = 0; i <= 255; i=i+1) begin
         memory[i] = 16'b001;
      end
      // data_out = 0; //should not exist if we want bram to be inferred
      valid_out = 0;
   end

   always @(posedge clk)
   begin
      // default
      valid_out <= 0;

      if(wr_en) begin
         memory[wr_addr] <= data_in;
      end
      if (rd_en) begin
         data_out <= memory[rd_addr];
         valid_out <= 1;
      end
   end
endmodule
