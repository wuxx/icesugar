module LCDC
(
    input  rst,
    input  pclk,

    output LCD_DE,
    output LCD_HSYNC,
    output LCD_VSYNC,

	output [4:0] LCD_B,
	output [5:0] LCD_G,
	output [4:0] LCD_R
);

    reg [15:0] x;
    reg [15:0] y;

    localparam vbp    = 16'd12; 
	localparam vpulse = 16'd1; 
	localparam vact   = 16'd272;
	localparam vfp    = 16'd1; 
	
	localparam hbp    = 16'd43; 
	localparam hpulse = 16'd1; 
	localparam hact   = 16'd480;
	localparam hfp    = 16'd2;    

    /*
    localparam vbp = 16'd12; 
	localparam vpulse 	= 16'd11; 
	localparam vact  = 16'd272;
	localparam vfp= 16'd8; 
	
	localparam hbp = 16'd50; 
	localparam hpulse 	= 16'd10; 
	localparam hact  = 16'd480;
	localparam hfp= 16'd8;    
    */


    /*
	localparam vbp = 16'd0; //6
	localparam vpulse 	= 16'd5; 
	localparam vact  = 16'd480;
	localparam vfp= 16'd45; //62

	localparam hbp = 16'd182; 
	localparam hpulse 	= 16'd1; 
	localparam hact  = 16'd800;
	localparam hfp= 16'd210;
    */

    localparam xmax = hact + hbp + hfp;  	
    localparam ymax = vact + vbp + vfp;

    always @( posedge pclk or negedge rst )begin
        if( !rst ) begin
            y <= 16'b0;    
            x <= 16'b0;
            end
        else if( x == xmax ) begin
            x <= 16'b0;
            y <= y + 1'b1;
            end
        else if( y == ymax ) begin
            y <=  16'b0;
            x <=  16'b0;
            end
        else
            x <= x + 1'b1;
    end

    assign  LCD_HSYNC = (( x >= hpulse )&&( x <= (xmax-hfp))) ? 1'b0 : 1'b1;
	assign  LCD_VSYNC = (( y >= vpulse )&&( y <= (ymax-0) ))  ? 1'b0 : 1'b1;

    assign  LCD_DE = (  ( x >= hbp )&&
                        ( x <= xmax-hfp ) &&
                        ( y >= vbp ) &&
                        ( y <= ymax-vfp-1 ))  ? 1'b1 : 1'b0;

    assign  LCD_R =  x<= (hbp + hpulse +  80)? 5'd16 : 
                    (x<= (hbp + hpulse + 160)? 5'd31 :  5'd0);

    assign  LCD_G =  (x>= (hbp + hpulse +  160) && x<= (hbp + hpulse +  240))? 6'd32 : 
                    ((x>= (hbp + hpulse +  240) && x<= (hbp + hpulse +  320))? 6'd63 : 6'd0);

    assign  LCD_B =  (x>= (hbp + hpulse +  320) && x<= (hbp + hpulse +  400))? 5'd16 : 
                    ((x>= (hbp + hpulse +  400) && x<= (hbp + hpulse +  480))? 5'd31 : 6'd0);
                        

    /*
    assign  LCD_R   =   (x< (hbp + hpulse +  80))? 5'd0 : 
                        (x< (hbp + hpulse + 160)? 5'd6 :    
                        (x< (hbp + hpulse + 240)? 5'd12 :    
                        (x< (hbp + hpulse + 320)? 5'd18 :    
                        (x< (hbp + hpulse + 400)? 5'd24 :    
                        (x< (hbp + hpulse + 480)? 5'd31 :  5'd0 )))));
    assign  LCD_G = 6'b000000;
    assign  LCD_B = 5'b00000;
    */

endmodule
