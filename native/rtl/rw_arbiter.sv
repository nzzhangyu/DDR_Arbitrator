`timescale 1ns/1ps

// Read/write request arbiter.
// - Builds service request descriptors.
// - Prioritizes urgent traffic.
// - Advances 2:1 write/read round-robin slots.
module rw_arbiter #(
    parameter logic [8:0] WR_BURST_NUM = 9'd256,
    parameter logic [9:0] RD_BURST_NUM = 10'd512
) (
    input  logic        ui_clk,
    input  logic        ui_clk_sync_rst,
    input  logic        rst_local_t_ddr_clk,
    input  logic        make_data_on_edge,
    input  logic        in_arb,
    input  logic        ddr_wr_req,
    input  logic        ddr_rd_req_qual,
    input  logic        wr_level_urgent,
    input  logic        rd_level_urgent,
    input  logic        wr_fifo_valid,
    input  logic [14:0] wr_fifo_rd_data_count,
    input  logic        rd_fifo_has_grant_space,
    input  logic [9:0]  rd_available_len,

    output logic [1:0]  arb_grant,
    output logic [9:0]  wr_req_len,
    output logic [9:0]  rd_req_len,
    output logic        wr_req_urgent,
    output logic        rd_req_urgent
);

    localparam logic [1:0] GRANT_NONE  = 2'd0;
    localparam logic [1:0] GRANT_WRITE = 2'd1;
    localparam logic [1:0] GRANT_READ  = 2'd2;

    localparam logic [1:0] ARB_SLOT_WRITE0 = 2'd0;
    localparam logic [1:0] ARB_SLOT_WRITE1 = 2'd1;
    localparam logic [1:0] ARB_SLOT_READ   = 2'd2;

    logic [1:0] arb_slot;
    logic       wr_req_valid;
    logic       rd_req_valid;
    logic       normal_grant_fire;

    assign wr_req_len    = {1'b0, fifo_count_to_burst_len(wr_fifo_rd_data_count,
                                                           wr_fifo_valid)};
    assign rd_req_len    = min2_10(rd_available_len, RD_BURST_NUM);
    assign wr_req_valid  = ddr_wr_req;
    assign rd_req_valid  = ddr_rd_req_qual &&
                            rd_fifo_has_grant_space &&
                            (~wr_level_urgent);
    assign wr_req_urgent = wr_req_valid && wr_level_urgent;
    assign rd_req_urgent = rd_req_valid && rd_level_urgent;

    assign normal_grant_fire = in_arb &&
                               ((arb_grant == GRANT_WRITE) ||
                                (arb_grant == GRANT_READ)) &&
                               (~wr_req_urgent) &&
                               (~rd_req_urgent) &&
                               (((arb_slot == ARB_SLOT_WRITE0) &&
                                 (arb_grant == GRANT_WRITE)) ||
                                ((arb_slot == ARB_SLOT_WRITE1) &&
                                 (arb_grant == GRANT_WRITE)) ||
                                ((arb_slot == ARB_SLOT_READ) &&
                                 (arb_grant == GRANT_READ)));

    // Round-robin slot.
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst || rst_local_t_ddr_clk || make_data_on_edge) begin
            arb_slot <= ARB_SLOT_WRITE0;
        end
        else if (normal_grant_fire) begin
            unique case (arb_slot)
                ARB_SLOT_WRITE0: arb_slot <= ARB_SLOT_WRITE1;
                ARB_SLOT_WRITE1: arb_slot <= ARB_SLOT_READ;
                default:         arb_slot <= ARB_SLOT_WRITE0;
            endcase
        end
    end

    // Grant selection.
    always_comb begin
        arb_grant = GRANT_NONE;

        if (wr_req_urgent) begin
            arb_grant = GRANT_WRITE;
        end
        else if (rd_req_urgent) begin
            arb_grant = GRANT_READ;
        end
        else begin
            unique case (arb_slot)
                ARB_SLOT_WRITE0,
                ARB_SLOT_WRITE1: begin
                    if (wr_req_valid) begin
                        arb_grant = GRANT_WRITE;
                    end
                    else if (rd_req_valid) begin
                        arb_grant = GRANT_READ;
                    end
                end

                default: begin
                    if (rd_req_valid) begin
                        arb_grant = GRANT_READ;
                    end
                    else if (wr_req_valid) begin
                        arb_grant = GRANT_WRITE;
                    end
                end
            endcase
        end
    end

    function automatic logic [8:0] fifo_count_to_burst_len(
        input logic [14:0] fifo_count,
        input logic        fifo_valid
    );
        if (fifo_count >= WR_BURST_NUM) begin
            fifo_count_to_burst_len = WR_BURST_NUM;
        end
        else if (fifo_count != 0) begin
            fifo_count_to_burst_len = {1'b0, fifo_count[7:0]};
        end
        else if (fifo_valid) begin
            fifo_count_to_burst_len = 9'd1;
        end
        else begin
            fifo_count_to_burst_len = '0;
        end
    endfunction

    function automatic logic [9:0] min2_10(
        input logic [9:0] a,
        input logic [9:0] b
    );
        min2_10 = (a < b) ? a : b;
    endfunction

endmodule
