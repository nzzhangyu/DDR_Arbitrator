// Native DDR controller simulation configuration.
//
// The checked-in default uses the real MIG model. Define FAST_MOCK from the
// simulator command line to select the lightweight native-app model instead.
`ifndef FAST_MOCK
`define MIG
`endif
