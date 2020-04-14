//light up the leds depending on each switch (careful, leds are active low, but so are the switches)

module switch(input [3:0] SW, output LED_R, output LED_G, output LED_B);
      
  assign LED_R = SW[0];
  assign LED_G = SW[1];
  assign LED_B = SW[2];

endmodule
