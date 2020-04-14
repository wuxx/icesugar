module music(clk, speaker);
input clk;
output speaker;

reg [27:0] tone;
always @(posedge clk) tone <= tone+1;

wire [5:0] fullnote = tone[27:22];

wire [2:0] octave;
wire [3:0] note;
divide_by12 divby12(.numer(fullnote[5:0]), .quotient(octave), .remain(note));

reg [10:0] clkdivider;
always @(note)
case(note)
  0: clkdivider = (512-1) << 2; // A 
  1: clkdivider = (483-1) << 2; // A#/Bb
  2: clkdivider = (456-1) << 2; // B 
  3: clkdivider = (431-1) << 2; // C 
  4: clkdivider = (406-1) << 2; // C#/Db
  5: clkdivider = (384-1) << 2; // D 
  6: clkdivider = (362-1) << 2; // D#/Eb
  7: clkdivider = (342-1) << 2; // E 
  8: clkdivider = (323-1) << 2; // F 
  9: clkdivider = (304-1) << 2; // F#/Gb
  10: clkdivider = (287-1) << 2; // G 
  11: clkdivider = (271-1) << 2; // G#/Ab
  12: clkdivider = 0; // should never happen
  13: clkdivider = 0; // should never happen
  14: clkdivider = 0; // should never happen
  15: clkdivider = 0; // should never happen
endcase

reg [8:0] counter_note;
always @(posedge clk) if(counter_note==0) counter_note <= clkdivider; else counter_note <= counter_note-1;

reg [7:0] counter_octave;
always @(posedge clk)
if(counter_note==0)
begin
 if(counter_octave==0)
  counter_octave <= (octave==0?255:octave==1?127:octave==2?63:octave==3?31:octave==4?15:7);
 else
  counter_octave <= counter_octave-1;
end

reg speaker;
always @(posedge clk) if(counter_note==0 && counter_octave==0) speaker <= ~speaker;
endmodule
