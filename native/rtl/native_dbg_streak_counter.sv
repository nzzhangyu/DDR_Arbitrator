`timescale 1ns/1ps

module native_dbg_streak_counter #(
    parameter int CNT_WIDTH = 32
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 active,
    output logic [CNT_WIDTH-1:0] cur,
    output logic [CNT_WIDTH-1:0] max
);

    logic [CNT_WIDTH-1:0] next_cur;

    assign next_cur = (&cur) ? cur : (cur + {{(CNT_WIDTH-1){1'b0}}, 1'b1});

    always_ff @(posedge clk) begin
        if (rst) begin
            cur <= '0;
            max <= '0;
        end
        else if (active) begin
            cur <= next_cur;
            if (next_cur > max) begin
                max <= next_cur;
            end
        end
        else begin
            cur <= '0;
        end
    end

endmodule
