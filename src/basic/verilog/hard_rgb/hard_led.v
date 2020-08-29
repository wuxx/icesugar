`default_nettype none


`define BLUEPWM  RGB0PWM
`define REDPWM   RGB1PWM
`define GREENPWM RGB2PWM


// Refer to "iCE40 LED Driver Usage Guide" for more details

module hard_led (
    output LED_R,
    output LED_G,
    output LED_B
);

    // Courtesy of https://github.com/AlexKly/iCE40UltraPlusMDP-RGBLED

    wire        inn_clk;

    reg         red_pwm;
    reg         green_pwm;
    reg         blue_pwm;
    reg         led_en;
    reg         led_cs;
    reg         led_exe;

    reg [3:0]   led_addr;
    reg [7:0]   led_dat;

    localparam  IDLE            = 4'b0000;
    localparam  LEDDCR0         = 4'b1000;
    localparam  LEDDBR          = 4'b1001;
    localparam  LEDDONR         = 4'b1010;
    localparam  LEDDOFR         = 4'b1011;
    localparam  LEDDBCRR        = 4'b0101;
    localparam  LEDDBCFR        = 4'b0110;
    localparam  LEDDPWRR        = 4'b0001;
    localparam  LEDDPWRG        = 4'b0010;
    localparam  LEDDPWRB        = 4'b0011;
    localparam  DONE            = 4'b1111;

    reg  [3:0]  next_led_addr   = IDLE;

    always @(posedge inn_clk)
    begin

        led_addr                <= next_led_addr;

        case (next_led_addr)
            IDLE: begin
                led_en          <= 0;
                led_cs          <= 0;
                led_exe         <= 1;
                led_dat         <= 8'b00000000;
                next_led_addr   <= LEDDCR0;
            end
            LEDDCR0: begin
                // LED Driver Control Register 0
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b11010110;
                next_led_addr   <= LEDDBR;
            end
            LEDDBR: begin
                // LED Driver Pre-scale Register
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b11101101;
                next_led_addr   <= LEDDONR;
            end
            LEDDONR: begin
                // LED Driver ON Time Register
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b00011001;
                next_led_addr   <= LEDDOFR;
            end
            LEDDOFR: begin
                // LED Driver OFF Time Register
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b00011001;
                next_led_addr   <= LEDDBCRR;
            end
            LEDDBCRR: begin
                // LED Driver Breathe On Control Register
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b11100011;
                next_led_addr   <= LEDDBCFR;
            end
            LEDDBCFR: begin
                // LED Driver Breathe Off Control Register
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b10100011;
                next_led_addr   <= LEDDPWRR;
            end
            LEDDPWRR: begin
                // LED Driver Pulse Width Register for RED
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b11111111;
                next_led_addr   <= LEDDPWRG;
            end
            LEDDPWRG: begin
                // LED Driver Pulse Width Register for GREEN
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b11111111;
                next_led_addr   <= LEDDPWRB;
            end
            LEDDPWRB: begin
                // LED Driver Pulse Width Register for BLUE
                led_en          <= 1;
                led_cs          <= 1;
                led_exe         <= 0;
                led_dat         <= 8'b11111111;
                next_led_addr   <= DONE;
            end
            DONE: begin
                led_en          <= 0;
                led_cs          <= 0;
                led_exe         <= 1;
                led_dat         <= 8'b00000000;
                next_led_addr   <= DONE;
            end
        endcase
    end

    // High-frequency on-chip oscillator
    SB_HFOSC SB_HFOSC_INST (
        .CLKHFPU                (1'b1),
        .CLKHFEN                (1'b1),
        .CLKHF                  (inn_clk),
    );

    defparam SB_HFOSC_INST.CLKHF_DIV = "0b00";

    // RGB PWM IP
    SB_LEDDA_IP SB_LEDDA_IP_INST (
        .LEDDCS                 (led_cs),
        .LEDDCLK                (inn_clk),
        .LEDDDAT7               (led_dat[7]),
        .LEDDDAT6               (led_dat[6]),
        .LEDDDAT5               (led_dat[5]),
        .LEDDDAT4               (led_dat[4]),
        .LEDDDAT3               (led_dat[3]),
        .LEDDDAT2               (led_dat[2]),
        .LEDDDAT1               (led_dat[1]),
        .LEDDDAT0               (led_dat[0]),
        .LEDDADDR3              (led_addr[3]),
        .LEDDADDR2              (led_addr[2]),
        .LEDDADDR1              (led_addr[1]),
        .LEDDADDR0              (led_addr[0]),
        .LEDDDEN                (led_en),
        .LEDDEXE                (led_exe),
        // The signal LEDDRST is documented, but doesn't really exist

        .PWMOUT0                (red_pwm),
        .PWMOUT1                (green_pwm),
        .PWMOUT2                (blue_pwm),
    );
    
    // RGB LED driver
    SB_RGBA_DRV SB_RGBA_DRV_INST (
        .RGB0                   (LED_R),
        .RGB1                   (LED_G),
        .RGB2                   (LED_B),
        .RGBLEDEN               (1'b1),
        .`REDPWM                (red_pwm),
        .`GREENPWM              (green_pwm),
        .`BLUEPWM               (blue_pwm),
        .CURREN                 (1'b1),
    );

    defparam SB_RGBA_DRV_INST.CURRENT_MODE = "0b0";
    defparam SB_RGBA_DRV_INST.RGB0_CURRENT = "0b000011";
    defparam SB_RGBA_DRV_INST.RGB1_CURRENT = "0b000011";
    defparam SB_RGBA_DRV_INST.RGB2_CURRENT = "0b000011";

endmodule // hard_led
