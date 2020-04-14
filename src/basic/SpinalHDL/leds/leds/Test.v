// Generator : SpinalHDL v1.4.0    git head : ecb5a80b713566f417ea3ea061f9969e73770a7f
// Date      : 13/04/2020, 04:21:48
// Component : Test



module Test (
  output reg [2:0]    io_led,
  input               clk,
  input               reset 
);
  reg        [31:0]   status;

  always @ (*) begin
    io_led[0] = status[23];
    io_led[1] = status[25];
    io_led[2] = status[27];
  end

  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      status <= 32'h0;
    end else begin
      status <= (status + 32'h00000001);
    end
  end


endmodule
