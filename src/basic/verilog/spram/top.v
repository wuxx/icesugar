//Simple test of the spram, use a state machine to write values in ram, then
//read them. The values written in memory is just the colours of a rgb led

module top(input [3:0] SW, input clk, output LED_R, output LED_G, output LED_B);

  reg [7:0] state;

  reg [31:0] counter;

  //access to spram
  reg [15:0] ram_addr;
  wire [15:0] ram_data_in;
  wire [15:0] ram_data_out;
  wire ram_wren;

  parameter IDLE = 0, INIT0 = IDLE+1, INIT1=INIT0+1, INIT2=INIT1+1, INIT3=INIT2+1, RUN = INIT3+1 ;

  reg [2:0] led;

  //leds are active low
  assign LED_R = ~led[0];
  assign LED_G = ~led[1];
  assign LED_B = ~led[2];

  SB_SPRAM256KA spram
  (
    .ADDRESS(ram_addr),
    .DATAIN(ram_data_in),
    .MASKWREN({ram_wren, ram_wren, ram_wren, ram_wren}),
    .WREN(ram_wren),
    .CHIPSELECT(1'b1),
    .CLOCK(clk),
    .STANDBY(1'b0),
    .SLEEP(1'b0),
    .POWEROFF(1'b1),
    .DATAOUT(ram_data_out)
  );

  initial begin
      state <= INIT0;
      led <= 3'b000;
      counter <= 0;
  end

  always @(posedge clk)
  begin

    ram_wren <= 1'b0;

    case(state)
    IDLE:
    begin
    end
    INIT0:
    begin
      ram_addr <= 16'b00;
      ram_data_in <= 16'b001; //write red
      ram_wren <= 1'b1;
      state <= INIT1;
    end
    INIT1:
    begin
      ram_addr <= 16'b01;
      ram_data_in <= 16'b010; //write green
      ram_wren <= 1'b1;
      state <= INIT2;
    end
    INIT2:
    begin
      ram_addr <= 16'b10;
      ram_data_in <= 16'b100; //write blue
      ram_wren <= 1'b1;
      state <= INIT3;
    end
    INIT3:
    begin
      ram_addr <= 16'b11;
      ram_data_in <= 16'b111; //write white
      ram_wren <= 1'b1;
      state <= RUN;
    end
    RUN:
    begin
      counter <= counter + 1;

      //incrment address every ~sec at 12Mhz
      if(counter == 32'h1000000) begin
        ram_addr[1:0] <= ram_addr[1:0] + 1;
      end
      if(counter == 32'h1000002) begin //must wait two cycles to have data
         led <= ram_data_out[2:0];
         counter <= 0;
      end

    end
    endcase


  end

endmodule
