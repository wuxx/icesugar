//manualy using the bram to implement a small memory

module explicit_bram(input wire clk, input wire rd_en, input wire wr_en, input wire [7:0] rd_addr, input wire [7:0] wr_addr, input wire [15:0] data_in, output reg [15:0] data_out, output reg valid_out);

   wire [15:0] rdata;
   reg [10:0] raddr;
   reg [10:0] waddr;
   reg [15:0] mask;
   reg [15:0] wdata;
   reg rclke;
   reg re;
   reg wclke;
   reg we;

   SB_RAM40_4K SB_RAM40_4K_inst(
      .RDATA(rdata), .RADDR(raddr), .WADDR(waddr), .MASK(mask), .WDATA(wdata), .RCLKE(rclke), .RCLK(clk), .RE(re), .WCLKE(wclke), .WCLK(clk), .WE(we)
   );

   initial begin
      raddr = 0;
      waddr = 0;
      mask = 0; //active low
      wdata = 0;
      rclke = 1;
      re = 0;
      wclke = 1;
      we = 0;
   end

   always @(posedge clk)
   begin

      if(wr_en == 1) begin
         waddr <= wr_addr;
         wdata <= data_in;
         we <= 1;
      end
      if (rd_en == 1) begin
         raddr <= rd_addr;
         re <= 1;
         valid_out <= 1;
         data_out <= rdata;
      end
   end
endmodule
