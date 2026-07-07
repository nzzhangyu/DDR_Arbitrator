`timescale 1ns/1ps

// Read/write request arbiter.
// - Prioritizes urgent traffic.
// - Advances 2:1 write/read round-robin slots.
module rw_arbiter (
    input  logic        i_ui_clk,
    input  logic        i_arbiter_rst,
    input  logic        i_arbiter_clear,
    input  logic        i_in_arb,
    input  logic        i_wr_req_valid,
    input  logic        i_rd_req_valid,
    input  logic        i_wr_req_urgent,
    input  logic        i_rd_req_urgent,

    output logic [1:0]  o_arb_grant
);

    typedef enum logic [1:0] {
        GRANT_NONE,
        GRANT_WRITE,
        GRANT_READ
    } grant_t;

    typedef enum logic [1:0] {
        ARB_SLOT_WRITE0,
        ARB_SLOT_WRITE1,
        ARB_SLOT_READ
    } arb_slot_t;

    grant_t    arb_grant_i;
    arb_slot_t arb_slot;
    logic      normal_grant_fire;

    assign o_arb_grant = arb_grant_i;

    assign normal_grant_fire = i_in_arb && 
                                ((arb_grant_i == GRANT_WRITE) || (arb_grant_i == GRANT_READ)) && 
                                (~i_wr_req_urgent) && (~i_rd_req_urgent) &&
                               (((arb_slot == ARB_SLOT_WRITE0) && (arb_grant_i == GRANT_WRITE)) ||
                                ((arb_slot == ARB_SLOT_WRITE1) && (arb_grant_i == GRANT_WRITE)) ||
                                ((arb_slot == ARB_SLOT_READ) && (arb_grant_i == GRANT_READ)));

    // Round-robin slot.
    always_ff @(posedge i_ui_clk) begin
        if (i_arbiter_rst || i_arbiter_clear) begin
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
        arb_grant_i = GRANT_NONE;

        if (i_wr_req_urgent) begin
            arb_grant_i = GRANT_WRITE;
        end
        else if (i_rd_req_urgent) begin
            arb_grant_i = GRANT_READ;
        end
        else begin
            unique case (arb_slot)
                ARB_SLOT_WRITE0,
                ARB_SLOT_WRITE1: begin
                    if (i_wr_req_valid) begin
                        arb_grant_i = GRANT_WRITE;
                    end
                    else if (i_rd_req_valid) begin
                        arb_grant_i = GRANT_READ;
                    end
                end

                default: begin
                    if (i_rd_req_valid) begin
                        arb_grant_i = GRANT_READ;
                    end
                    else if (i_wr_req_valid) begin
                        arb_grant_i = GRANT_WRITE;
                    end
                end
            endcase
        end
    end

endmodule
