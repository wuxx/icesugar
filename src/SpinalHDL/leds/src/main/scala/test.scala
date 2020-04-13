package test

import spinal.core._
import spinal.lib._
import spinal.core.sim._

import ice40._

class Test() extends Component{
  val io = new Bundle {
    val led = out Bits(3 bits)
  }

  val status = Reg(UInt(32 bits)) init(0)

  status := status + 1
  io.led(0) := status(23)
  io.led(1) := status(25)
  io.led(2) := status(27)
}

object test {
  def compile_rtl(): Unit = {
    SpinalVerilog(new Test)
  }

  def main(args: Array[String]): Unit = {
    compile_rtl()
    compile.gen_compile("Test")
    compile.run_compile_sh("Test")
  }
}
