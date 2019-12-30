ins 1:
    "freq"

outs 1
 
init:
    phase = 0.0

    #build phase

perform:
    frequency : Signal
    sine_out  : Signal

    samplerate_minus_one = samplerate - 1.0
    twopi = 2 * PI

    sample:
        frequency = abs(in1)

        increment = frequency / samplerate_minus_one

        sine_out = cos(phase * twopi)
        
        out1 = sine_out

        phase += increment
        phase = phase mod 1.0
