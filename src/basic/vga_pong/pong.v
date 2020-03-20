// Pong VGA game
// (c) fpga4fun.com
// https://www.fpga4fun.com/PongGame.html

module pong(clk12, vga_h_sync, vga_v_sync, vga_R, vga_G, vga_B, vga_R1, vga_G1, vga_B1, vga_R2, vga_G2, vga_B2, vga_R3, vga_G3, vga_B3, quadA, quadB);
input clk12;
output vga_h_sync, vga_v_sync, vga_R, vga_G, vga_B, vga_R1, vga_G1, vga_B1, vga_R2, vga_G2, vga_B2, vga_R3, vga_G3, vga_B3;
input quadA, quadB;

wire inDisplayArea;
wire [9:0] CounterX;
wire [8:0] CounterY;
wire clk;
    /* 640x480 55Hz */
    /* icepll -o 31.5Mhz */
    /* please refer to http://tinyvga.com/vga-timing */
    SB_PLL40_PAD #(
                .FEEDBACK_PATH("SIMPLE"),
                .DIVR(4'b0000),         // DIVR =  0
                //.DIVF(7'b1010011),      // DIVF =  83
                .DIVF(7'b0111000),      // DIVF =  83
                .DIVQ(3'b101),          // DIVQ =  5
                .FILTER_RANGE(3'b001)   // FILTER_RANGE = 1
        ) uut (
                .RESETB(1'b1),
                .BYPASS(1'b0),
                .PACKAGEPIN(clk12),
                .PLLOUTCORE(clk)
                );



hvsync_generator syncgen(.clk(clk), .vga_h_sync(vga_h_sync), .vga_v_sync(vga_v_sync), 
  .inDisplayArea(inDisplayArea), .CounterX(CounterX), .CounterY(CounterY));

/////////////////////////////////////////////////////////////////
reg [8:0] PaddlePosition;
reg [2:0] quadAr, quadBr;
always @(posedge clk) quadAr <= {quadAr[1:0], quadA};
always @(posedge clk) quadBr <= {quadBr[1:0], quadB};

always @(posedge clk)
if(quadAr[2] ^ quadAr[1] ^ quadBr[2] ^ quadBr[1])
begin
	if(quadAr[2] ^ quadBr[1])
	begin
		if(~&PaddlePosition)        // make sure the value doesn't overflow
			PaddlePosition <= PaddlePosition + 1;
	end
	else
	begin
		if(|PaddlePosition)        // make sure the value doesn't underflow
			PaddlePosition <= PaddlePosition - 1;
	end
end

/////////////////////////////////////////////////////////////////
reg [9:0] ballX;
reg [8:0] ballY;
reg ball_inX, ball_inY;

always @(posedge clk)
if(ball_inX==0) ball_inX <= (CounterX==ballX) & ball_inY; else ball_inX <= !(CounterX==ballX+16);

always @(posedge clk)
if(ball_inY==0) ball_inY <= (CounterY==ballY); else ball_inY <= !(CounterY==ballY+16);

wire ball = ball_inX & ball_inY;

/////////////////////////////////////////////////////////////////
wire border = (CounterX[9:3]==0) || (CounterX[9:3]==79) || (CounterY[8:3]==0) || (CounterY[8:3]==59);
wire paddle = (CounterX>=PaddlePosition+8) && (CounterX<=PaddlePosition+120) && (CounterY[8:4]==27);
wire BouncingObject = border | paddle; // active if the border or paddle is redrawing itself

reg ResetCollision;
always @(posedge clk) ResetCollision <= (CounterY==500) & (CounterX==0);  // active only once for every video frame

reg CollisionX1, CollisionX2, CollisionY1, CollisionY2;
always @(posedge clk) if(ResetCollision) CollisionX1<=0; else if(BouncingObject & (CounterX==ballX   ) & (CounterY==ballY+ 8)) CollisionX1<=1;
always @(posedge clk) if(ResetCollision) CollisionX2<=0; else if(BouncingObject & (CounterX==ballX+16) & (CounterY==ballY+ 8)) CollisionX2<=1;
always @(posedge clk) if(ResetCollision) CollisionY1<=0; else if(BouncingObject & (CounterX==ballX+ 8) & (CounterY==ballY   )) CollisionY1<=1;
always @(posedge clk) if(ResetCollision) CollisionY2<=0; else if(BouncingObject & (CounterX==ballX+ 8) & (CounterY==ballY+16)) CollisionY2<=1;

/////////////////////////////////////////////////////////////////
wire UpdateBallPosition = ResetCollision;  // update the ball position at the same time that we reset the collision detectors

reg ball_dirX, ball_dirY;
always @(posedge clk)
if(UpdateBallPosition)
begin
	if(~(CollisionX1 & CollisionX2))        // if collision on both X-sides, don't move in the X direction
	begin
		ballX <= ballX + (ball_dirX ? -1 : 1);
		if(CollisionX2) ball_dirX <= 1; else if(CollisionX1) ball_dirX <= 0;
	end

	if(~(CollisionY1 & CollisionY2))        // if collision on both Y-sides, don't move in the Y direction
	begin
		ballY <= ballY + (ball_dirY ? -1 : 1);
		if(CollisionY2) ball_dirY <= 1; else if(CollisionY1) ball_dirY <= 0;
	end
end 

/////////////////////////////////////////////////////////////////
wire R = BouncingObject | ball | (CounterX[3] ^ CounterY[3]);
wire G = BouncingObject | ball;
wire B = BouncingObject | ball;

reg vga_R, vga_G, vga_B;
reg vga_R1, vga_G1, vga_B1;
reg vga_R2, vga_G2, vga_B2;
reg vga_R3, vga_G3, vga_B3;

always @(posedge clk)
begin
	vga_R <= R & inDisplayArea;
	vga_R1 <= R & inDisplayArea;
	vga_R2 <= R & inDisplayArea;
	vga_R3 <= R & inDisplayArea;

	vga_G <= G & inDisplayArea;
	vga_G1 <= G & inDisplayArea;
	vga_G2 <= G & inDisplayArea;
	vga_G3 <= G & inDisplayArea;

	vga_B <= B & inDisplayArea;
	vga_B1 <= B & inDisplayArea;
	vga_B2 <= B & inDisplayArea;
	vga_B3 <= B & inDisplayArea;
end

endmodule
