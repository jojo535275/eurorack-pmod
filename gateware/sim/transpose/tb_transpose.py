import sys
import pickle
import cocotb
import random
import math
from cocotb.clock import Clock
from cocotb.triggers import Timer, FallingEdge, RisingEdge, ClockCycles
from cocotb.handle import Force, Release

# Hack to import some helpers despite existing outside a package.
sys.path.append("..")
from util.i2s import *

@cocotb.test()
async def test_transpose_00(dut):

    sample_width = 16

    clock = Clock(dut.sample_clk, 5, units='us')
    cocotb.start_soon(clock.start())

    # Not needed at the moment as we aren't pipelining things
    #clock = Clock(dut.clk, 83, units='ns')
    #cocotb.start_soon(clock.start())

    dut.sample_in.value = 0
    dut.pitch.value = 5000*4

    # Clock in some zeroes so the delay lines are full of zeroes.

    for i in range(1024):
        await RisingEdge(dut.sample_clk)

    # Stimulate the pitch shifter with a sine wave and make sure
    # the output does not have any discontinuities

    data_out_last = None
    breaknext = False

    for i in range(2048):
        await RisingEdge(dut.sample_clk)

        data_in = int(1000*math.sin(i / 100))

        dut.sample_in.value = bits_from_signed(data_in, sample_width)
        data_out = signed_from_bits(dut.sample_out.value, sample_width)

        print(f"i={i} in:", data_in)
        print(f"i={i} out:", data_out)

        if data_out_last is not None:
            print(f"del0: {int(dut.delay_out0)}")
            print(f"env0: {int(dut.env0)}")
            print(f"del1: {int(dut.delay_out1)}")
            print(f"env1: {int(dut.env1)}")
            if breaknext:
                print("FOUND A DISCONTINUITY - failing...")
                assert(False)
                break
            if abs(data_out - data_out_last) > 50:
                # Found a discontinuity in the output
                print("=========================")
                # It's useful to show one more sample after
                # the discontinuity for debugging.
                breaknext = True

        data_out_last = data_out
