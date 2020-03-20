//light up the leds according to a counter to cycle through every one

/*
   b[25] b[24] b[23]
   0     0     0    black   (all off)
   0     0     1    red
   0     1     0    green
   0     1     1    yellow  (red + green)
   1     0     0    blue
   1     0     1    magenta (red + blue)
   1     1     0    cyan    (green + blue)
   1     1     1    white
*/

module top(input [3:0] SW, input clk, output LED_R, output LED_G, output LED_B);
   reg [25:0] counter;

   assign LED_R = ~counter[23];
   assign LED_G = ~counter[24];
   assign LED_B = ~counter[25];

   initial begin
      counter = 0;
   end

   always @(posedge clk)
   begin
      counter <= counter + 1;
   end
endmodule // top
