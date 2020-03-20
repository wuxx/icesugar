`include "pwm.v"

//light up the leds using the pwm module, starts at lowest value and then goes slowly to
//128, then back to 0

module top(input [3:0] SW, input clk, output LED_R, output LED_G, output LED_B);
  
  reg [17:0] counter;
  reg [6:0] val_pwm; //only make it go to 128 (half brightness)
  
  //io for the pwm module
  wire pwm_en_write;
  wire [7:0] pwm_value_write;
  wire pwm_out;
  
  pwm pwm_inst(
    .clk(clk), .en(pwm_en_write), .value_input(pwm_value_write), .out(pwm_out)
  );
  
  //leds are active low
  assign LED_R = ~pwm_out;
  assign LED_G = ~pwm_out;
  assign LED_B = ~pwm_out;
  
  initial begin
      pwm_en_write = 1;
      pwm_value_write = 0;
      val_pwm = 0;
  end
  
  always @(posedge clk)
  begin
    
    pwm_en_write = 0;
    counter <= counter + 1;
    
    if(counter == 0) begin
      val_pwm <= val_pwm + 1; //increase the width of pwm
      pwm_en_write = 1;
      pwm_value_write <= val_pwm;
    end
  end

endmodule
