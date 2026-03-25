/*
File Name : TwoLevel_Local_Predictor.v
Description: Two-Level Local Branch Predictor (LHT + PHT)
*/

module TwoLevelLocalPredictor #(
    parameter PC_BITS = 6,       // Bits of PC to index LHT (64 entries)
    parameter HIST_BITS = 4      // 4-bit history -> 16 PHT entries
)(
    input wire clk,            
    input wire reset,          
    
    // Fetch Stage Interface
    input wire [31:0] fetch_pc,       
    output reg prediction,
    output wire [HIST_BITS-1:0] predict_history_out, // Pipeline must carry this!
    
    // Execute Stage Interface (Update)
    input wire update_en,               // HIGH when branch resolves
    input wire [31:0] update_pc,        // PC of the resolving branch
    input wire [HIST_BITS-1:0] update_history_in, // The history used during fetch
    input wire branch_taken             // Actual outcome
);

    // States for the 2-bit saturating counter
    parameter STRONGLY_NOT_TAKEN = 2'b00;
    parameter WEAKLY_NOT_TAKEN   = 2'b01;
    parameter WEAKLY_TAKEN       = 2'b10;
    parameter STRONGLY_TAKEN     = 2'b11;

    // 1. Local History Table (LHT)
    // Stores the shift register history for each PC
    reg [HIST_BITS-1:0] lht [0:(1<<PC_BITS)-1];
    
    // 2. Pattern History Table (PHT)
    // Stores the 2-bit counters, indexed by the history pattern
    reg [1:0] pht [0:(1<<HIST_BITS)-1];

    // Combinational Prediction Logic (Fetch Stage) 
    wire [PC_BITS-1:0] fetch_idx = fetch_pc[PC_BITS+1:2];
    
    // Output the history so the pipeline registers can capture it
    assign predict_history_out = lht[fetch_idx];

    // Read the PHT combinationally
    always @(*) begin
        case (pht[predict_history_out])
            STRONGLY_NOT_TAKEN, WEAKLY_NOT_TAKEN: prediction = 1'b0; 
            WEAKLY_TAKEN, STRONGLY_TAKEN:         prediction = 1'b1; 
            default:                              prediction = 1'b0;
        endcase
    end

    // Sequential Update Logic (Execute Stage) 
    integer i;
    wire [PC_BITS-1:0] update_idx = update_pc[PC_BITS+1:2];

    always @(posedge clk) begin
        if (reset) begin
            // Initialize both tables
            for (i = 0; i < (1<<PC_BITS); i = i + 1) begin
                lht[i] <= 0; // Initialize history to 0s
            end
            for (i = 0; i < (1<<HIST_BITS); i = i + 1) begin
                pht[i] <= WEAKLY_TAKEN; // Initialize counters
            end
        end else if (update_en) begin
            
            // 1. Update the PHT counter using the OLD history passed from the pipeline
            case ({pht[update_history_in], branch_taken})
                {STRONGLY_NOT_TAKEN, 1'b0}: pht[update_history_in] <= STRONGLY_NOT_TAKEN;
                {STRONGLY_NOT_TAKEN, 1'b1}: pht[update_history_in] <= WEAKLY_NOT_TAKEN;
                
                {WEAKLY_NOT_TAKEN, 1'b0}:   pht[update_history_in] <= STRONGLY_NOT_TAKEN;
                {WEAKLY_NOT_TAKEN, 1'b1}:   pht[update_history_in] <= WEAKLY_TAKEN;
                
                {WEAKLY_TAKEN, 1'b0}:       pht[update_history_in] <= WEAKLY_NOT_TAKEN;
                {WEAKLY_TAKEN, 1'b1}:       pht[update_history_in] <= STRONGLY_TAKEN;
                
                {STRONGLY_TAKEN, 1'b0}:     pht[update_history_in] <= WEAKLY_TAKEN;
                {STRONGLY_TAKEN, 1'b1}:     pht[update_history_in] <= STRONGLY_TAKEN;
            endcase

            // 2. Update the LHT for this specific PC by shifting in the actual outcome
            lht[update_idx] <= {update_history_in[HIST_BITS-2:0], branch_taken};
        end
    end

endmodule
