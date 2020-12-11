//plug pmod-led on PMOD2

module switch(input CLK, output [7:0] LED);
      
    reg [25:0] counter;
    wire lclk = counter[22];

    initial begin
        LED = 8'b11111110;
    end

    always @(posedge CLK)
    begin
        counter <= counter + 1;
    end

    always @(posedge lclk)
    begin
        LED <= {LED[6:0], LED[7]};
    end


endmodule
