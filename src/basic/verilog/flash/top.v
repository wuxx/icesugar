`include "spi_master.v"

//this top verilog design sends a read request as well as an address (0x100000 or 1MB) to to the master spi module.
//in flash master, prog.hex is written in the flash at the 0x100000 offset and contains 00, 01, 02, 03, 04
//some of these values are read and displayed on the LED

module top(input [3:0] SW, input clk, output LED_R, output LED_G, output LED_B, output SPI_SCK, output SPI_SS, input SPI_MOSI, output SPI_MISO, input [3:0] SW);

   reg spi_reset;
   wire spi_addr_buffer_free;
   reg spi_addr_en;
   reg [23:0] spi_addr_data;
   wire spi_rd_data_available;
   reg spi_rd_ack;
   wire [31:0] spi_rd_data;

   parameter IDLE = 0, INIT=IDLE+1, SEND_ADDR_SPI=INIT+1, WAIT_READ_DATA=SEND_ADDR_SPI+1, DISPLAY_LED=WAIT_READ_DATA+1;

   reg [3:0] state;

   //from ice40 ultraplus datasheet, the miso/mosi are inverted in the ice40 when in flash-prog mode
   //ice_MOSI is flash_MISO (in)
   //ice_MISO is flash_MOSI (out)
   spi_master spi_master_inst(.clk(clk), .reset(spi_reset),
      .SPI_SCK(SPI_SCK), .SPI_SS(SPI_SS), .SPI_MOSI(SPI_MISO), .SPI_MISO(SPI_MOSI),
      .addr_buffer_free(spi_addr_buffer_free), .addr_en(spi_addr_en), .addr_data(spi_addr_data),
      .rd_data_available(spi_rd_data_available), .rd_ack(spi_rd_ack), .rd_data(spi_rd_data)
   );

   reg [2:0] led;

   reg [23:0] spi_recv_data_reg;
   reg handle_data;

   reg [15:0] reg_bits_inversion;
   reg [31:0] counter;

   assign LED_R = ~led[0];
   assign LED_G = ~led[1];
   assign LED_B = ~led[2];

   initial begin
      spi_reset = 0;
      spi_addr_en = 0;
      spi_addr_data = 24'h100000; //1MB offset
      spi_rd_ack = 0;

      led = 0;
      spi_recv_data_reg = 0;
      handle_data = 0;

      state = INIT;

      counter = 0;
   end

   always @(posedge clk)
   begin

      //defaults
      spi_rd_ack <= 0;
      spi_addr_en <= 0;

      case (state)
      INIT: begin
         counter <= counter + 1;
         //wait a bit before starting the SPI
         //if the spi module is started immediately, the behaviour seems strange
         if(counter == 32'h1000000) begin
            state <= SEND_ADDR_SPI;
         end
      end
      SEND_ADDR_SPI: begin
         // spi_addr_data <= 24'h100000;
         spi_addr_en <= 1;
         state <= WAIT_READ_DATA;
      end
      WAIT_READ_DATA: begin
         if(spi_rd_data_available == 1) begin
            //reads the three LSB of the third byte, so 0x100002, which should be 0x02 (green)
            //31:24 is the first byte, 23:16 the second and 15:8 is the third
            led <= spi_rd_data[10:8];
            state <= DISPLAY_LED;
            spi_rd_ack <= 1; //resets the spi module back to read address
         end
      end

      DISPLAY_LED: begin
         //do nothing
      end
      endcase
   end

endmodule
