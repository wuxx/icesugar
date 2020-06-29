`default_nettype none

module top (
	input  clk,
    output ws_data
);

    localparam NUM_LEDS = 64;

    reg reset = 1;
    always @(posedge clk)
        reset <= 0;

    reg [18:0] count = 0;
    reg [1:0]  color_ind = 0;
    always @(posedge clk) begin
        count <= count + 1;
        if (&count) begin
            if (led_num == NUM_LEDS) begin
                led_num <= 0;
                color_ind <= color_ind + 1;
                case (color_ind)
                  2'b00 : led_rgb_data <= 24'h10_00_00;
                  2'b01 : led_rgb_data <= 24'h00_10_00;
                  2'b10 : led_rgb_data <= 24'h00_00_10;
                  2'b11 : led_rgb_data <= 24'h10_10_10;
		endcase
            end else
               led_num <= led_num + 1;
	end
    end

    reg [23:0] led_rgb_data = 24'h00_00_10;
    reg [7:0] led_num = 0;
    wire led_write = &count;

    ws2812 #(.NUM_LEDS(NUM_LEDS)) ws2812_inst(.data(ws_data), .clk(clk), .reset(reset), .rgb_data(led_rgb_data), .led_num(led_num), .write(led_write));

endmodule
