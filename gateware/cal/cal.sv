// Calibrator module.
//
// Convert between raw & 'calibrated' samples by removing DC offset
// and scaling for 4 counts / mV (i.e 14.2 fixed-point).
//
// This is essentially implemented as a pipelined 8 channel multiplier
// with 4 channels used for calibrating raw ADC counts and 4 channels
// used for calibrating output DAC counts.
//
// The calibration memory is created by following the calibration process
// documented in `cal.py`. This module only uses a single multiplier for
// all channels such that there are plenty left over for user logic.
//
// This module also checks jack inputs and sets calibrated samples to zero
// for any inputs for which a jack is not connected.

`default_nettype none

module cal #(
    parameter W = 16, // sample width
    parameter CAL_MEM_FILE = "cal/cal_mem.hex"
)(
    input rst,
    input clk_256fs,
    input clk_fs,
    input [7:0] jack,
    input signed [W-1:0] in0,
    input signed [W-1:0] in1,
    input signed [W-1:0] in2,
    input signed [W-1:0] in3,
    input signed [W-1:0] in4,
    input signed [W-1:0] in5,
    input signed [W-1:0] in6,
    input signed [W-1:0] in7,
    output logic signed [W-1:0] out0,
    output logic signed [W-1:0] out1,
    output logic signed [W-1:0] out2,
    output logic signed [W-1:0] out3,
    output logic signed [W-1:0] out4,
    output logic signed [W-1:0] out5,
    output logic signed [W-1:0] out6,
    output logic signed [W-1:0] out7
);

localparam N_CHANNELS = 8;
localparam LAST_CH_IX = 3'd7;

localparam CAL_ST_LATCH     = 3'd0,
           CAL_ST_ZERO      = 3'd1,
           CAL_ST_MULTIPLY  = 3'd2,
           CAL_ST_CLAMPL    = 3'd3,
           CAL_ST_CLAMPH    = 3'd4,
           CAL_ST_OUT       = 3'd5,
           CAL_ST_HALT      = 3'd6;

localparam int signed CLAMPL = -2**(W-1) + 1;
localparam int signed CLAMPH =  2**(W-1) - 1;

logic signed [W-1:0]     cal_mem [0:(2*N_CHANNELS)-1];
logic signed [(2*W)-1:0] out     [N_CHANNELS];
logic        [2:0]       ch;
logic        [2:0]       state;
logic                    l_clk_fs;

// Calibration memory for 8 channels stored as
// 2 bytes shift, 2 bytes multiply * 8 channels.
initial $readmemh(CAL_MEM_FILE, cal_mem);

always_ff @(posedge clk_256fs) begin

    if (rst) begin
        l_clk_fs <= 0;
        ch <= 0;
        state <= CAL_ST_LATCH;
        out[0] <= 0;
        out[1] <= 0;
        out[2] <= 0;
        out[3] <= 0;
        out[4] <= 0;
        out[5] <= 0;
        out[6] <= 0;
        out[7] <= 0;
    end else begin

        l_clk_fs <= clk_fs;

        // On rising clk_fs.
        if (clk_fs && (l_clk_fs != clk_fs)) begin
            state <= CAL_ST_LATCH;
            ch <= 0;
        end else begin
            ch <= ch + 1;
        end

        case (state)
            CAL_ST_LATCH: begin
                case (ch)
                    0: out[0] <= 32'(in0);
                    1: out[1] <= 32'(in1);
                    2: out[2] <= 32'(in2);
                    3: out[3] <= 32'(in3);
                    4: out[4] <= 32'(in4);
                    5: out[5] <= 32'(in5);
                    6: out[6] <= 32'(in6);
                    7: out[7] <= 32'(in7);
                endcase
                if (ch == LAST_CH_IX) state <= CAL_ST_ZERO;
            end
            CAL_ST_ZERO: begin
                out[ch] <= (out[ch] - 32'(cal_mem[{ch, 1'b0}]));
                if (ch == LAST_CH_IX) state <= CAL_ST_MULTIPLY;
            end
            CAL_ST_MULTIPLY: begin
                out[ch] <= (out[ch] * cal_mem[{ch, 1'b1}]) >>> 10;
                if (ch == LAST_CH_IX) state <= CAL_ST_CLAMPL;
            end
            CAL_ST_CLAMPL: begin
                out[ch] <= ((out[ch] < CLAMPL) ? CLAMPL : out[ch]);
                if (ch == LAST_CH_IX) state <= CAL_ST_CLAMPH;
            end
            CAL_ST_CLAMPH: begin
                out[ch] <= ((out[ch] > CLAMPH) ? CLAMPH : out[ch]);
                if (ch == LAST_CH_IX) state <= CAL_ST_OUT;
            end
            CAL_ST_OUT: begin
                // Calibrated input samples are zeroed if jack disconnected.
                out0  <= jack[0] ? out[0][W-1:0] : 0;
                out1  <= jack[1] ? out[1][W-1:0] : 0;
                out2  <= jack[2] ? out[2][W-1:0] : 0;
                out3  <= jack[3] ? out[3][W-1:0] : 0;
                out4  <= out[4][W-1:0];
                out5  <= out[5][W-1:0];
                out6  <= out[6][W-1:0];
                out7  <= out[7][W-1:0];
                state <= CAL_ST_HALT;
            end
            default: begin
                // Halt and do nothing.
            end
        endcase
    end
end

`ifdef COCOTB_SIM

`ifdef UNIT_TEST
initial begin
  $dumpfile ("cal.vcd");
  $dumpvars;
  #1;
end
`endif

// Shadow fake wires so we can look inside verilog arrays in vcd trace.
generate
  genvar idx;
  for(idx = 0; idx < 8; idx = idx+1) begin: register
    wire [31:0] out_dummy;
    assign out_dummy = out[idx];
  end
endgenerate
`endif

endmodule
