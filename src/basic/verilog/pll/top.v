//input external 12MHz clk disabled, as we are using the PLL with internal oscillator, having both don't seem possible
module top(input [3:0] SW, /*input clk,*/ output LED_R, output LED_G, output LED_B);
   wire clk_48mhz; //internal
   wire clk_10khz; //internal
   wire clk_24mhz;

   reg [2:0] led;
   reg [24:0] counter_slow;
   reg [24:0] counter_fast;

   //leds are active low
   assign LED_R = ~led[0];
   assign LED_G = ~led[1];
   assign LED_B = ~led[2];

   //internal oscillators seen as modules
   SB_HFOSC SB_HFOSC_inst(
      .CLKHFEN(1),
      .CLKHFPU(1),
      .CLKHF(clk_48mhz)
   );

   //10khz used for low power applications (or sleep mode)
   SB_LFOSC SB_LFOSC_inst(
      .CLKLFEN(1),
      .CLKLFPU(1),
      .CLKLF(clk_10khz)
   );

   // // PLL pad with external clock,
   // // outputs 32MHz
   // SB_PLL40_PAD #(
   //    .FEEDBACK_PATH("SIMPLE"),
   //    .PLLOUT_SELECT("GENCLK"),
   //    .DIVR(4'b0000),
   //    .DIVF(7'b1010100),
   //    .DIVQ(3'b101),
   //    .FILTER_RANGE(3'b001),
   //  ) SB_PLL40_CORE_inst (
   //    .RESETB(1'b1),
   //    .BYPASS(1'b0),
   //    .PACKAGEPIN(clk),
   //    .PLLOUTCORE(clk_32mhz),
   // );

   SB_PLL40_CORE #(
      .FEEDBACK_PATH("SIMPLE"),
      .PLLOUT_SELECT("GENCLK"),
      .DIVR(4'b0000),
      .DIVF(7'b0001111),
      .DIVQ(3'b101),
      .FILTER_RANGE(3'b100),
    ) SB_PLL40_CORE_inst (
      .RESETB(1'b1),
      .BYPASS(1'b0),
      .PLLOUTCORE(clk_24mhz),
      .REFERENCECLK(clk_48mhz)
   );

   initial begin
      led = 0;
      counter_slow = 0;
      counter_fast = 0;
   end

   always @(posedge clk_24mhz)
   begin
      counter_slow <= counter_slow + 1;
      if (counter_slow == 24*1024*1024) begin //will update led every second
         led[0] <= ~led[0];
         counter_slow <= 0;
      end
   end

   always @(posedge clk_48mhz)
   begin
      counter_fast <= counter_fast + 1;
      if (counter_fast == 24*1024*1024) begin //will update led every 1/2 seconds
         led[1] <= ~led[1];
         counter_fast <= 0;
      end
   end

endmodule
