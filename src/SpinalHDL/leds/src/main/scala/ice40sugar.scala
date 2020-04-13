package ice40

import java.io._
import scala.io.Source
import sys.process._
import scala.collection.immutable.Map

object compile {
  def gen_compile(topname: String): Unit = {
    val sh = 
    s"""#!/bin/sh
yosys -p "synth_ice40 -blif $topname.blif"  $topname.v
arachne-pnr -d 5k -P sg48 -p $topname.pcf $topname.blif -o $topname.asc
icepack $topname.asc $topname.bin
    """

    val compilesh = new PrintWriter("./compile.sh")

    compilesh.println(sh)
    compilesh.close()
  }

  def run_compile_sh(topname: String): Int = {
    "chmod +x ./compile.sh".!
    val exitCode = "./compile.sh".!
    exitCode
  }
}

