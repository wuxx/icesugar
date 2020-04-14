module calc(input clk, output correct);
   reg [3:0] state;
   reg [31:0] value;
   reg out_val;

   assign correct = out_val;

   initial begin
      state = 0;
      value = 0;
      out_val = 0;
   end

   always @(posedge clk)
   begin

      if(state < 15)
      begin
         state <= state + 1;
      end

      case (state)
      0: begin
         value <= 127;
      end
      1: begin
         value <= value + (value*5);
      end
      2: begin
         value <= value + (value*value);
      end
      3: begin
         if(value == 581406)
         begin
            out_val <= 1;
         end
      end
      default: begin
      end
      endcase

   end
endmodule
