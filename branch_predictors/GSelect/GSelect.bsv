`ifdef USING_TOOOBA
import Types::*;
import ProcTypes::*;
`endif
import BrPred::*;
import Ehr::*;

import Vector::*;
import RegFile::*;
import Assert::*;
import TRegFile::*;
import ValueWithConfidence::*;

export GSelectDirPredToken;
export mkGSelect;


// This branch predictor uses bits from the PC concatenated with global history to index a table of saturation counters.
// Booleans with a 1-bit counter (ValueWithHysteresis) are used in place of 2-bit saturating counters.
// The predictor size is NumCounterBits * 2^(NumPcBits+(NumGlobalHistoryItems*SizeOf(Result)).

// A Boolean value for whether a branch should be (or was) taken.
typedef Bool Result;

// The number of bits from the PC to index the table of saturating counters.
// The bits used exclude the two lowest bits of the PC.
// 1 <= NumPcBits <= BrPred::AddrSz - 2.
typedef 4 NumPcBits;
typedef Bit#(NumPcBits) ChoppedAddr;

// The number of global branch results to keep.
// 1 <= NumGlobalHistoryItems.
typedef 8 NumGlobalHistoryItems;
// The first item is the newest.
typedef Vector#(NumGlobalHistoryItems, Result) GlobalHistory;

typedef TAdd#(NumPcBits, TMul#(NumGlobalHistoryItems, SizeOf#(Result))) NumIndexBits;
typedef Bit#(NumIndexBits) Index;

typedef UInt#(8) GSelectDirPredToken;
typedef TExp#(SizeOf#(GSelectDirPredToken)) NumPastPreds;

typedef struct {
    Index index;
    Result prediction;
    GlobalHistory globalHistory;  // Some redundancy with index.
} GSelectTrainInfo deriving(Bits, Eq, FShow);

typedef struct {
    GSelectDirPredToken token;
    Maybe#(Result) actual;  // Valid if explicit update, Invalid if implicit update.
} UpdateInfo deriving(Bits);


module mkGSelect(DirPredictor#(GSelectDirPredToken));
    staticAssert(1 <= valueOf(NumPcBits) && valueOf(NumPcBits) <= valueOf(AddrSz) - 2, "Must have 1 <= NumPcBits <= AddrSz - 2");
    staticAssert(1 <= valueOf(NumGlobalHistoryItems), "Must have 1 <= NumGlobalHistoryItems");


    // The lower `NumPcBits` bits (minus 2 lowest) of the PC for first instruction in the superscalar batch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkRegU;
    // The global history of conditional branch results (taken/not taken). The MSB is the oldest result.
    Reg#(GlobalHistory) globalHistory <- mkRegU;
    TRegFile#(
        Index,
        ValueWithConfidence#(Result),
        TAdd#(SupSize, TAdd#(SupSize, 1)),
        TAdd#(SupSize, 1)
    ) predictionTable <- mkTRegFile(
        replicate(ValueWithConfidence {value: False, confidence: 0})
    );
    // Registers to store the global history for this superscalar batch.
    Vector#(SupSize, RWire#(Result)) batchHistory <- replicateM(mkUnsafeRWire);
    Ehr#(SupSize, GSelectDirPredToken) currentPredictionToken <- mkEhr(0);
    TRegFile#(
        GSelectDirPredToken,
        Maybe#(GSelectTrainInfo),
        TAdd#(SupSize, 1),
        TAdd#(SupSize, TAdd#(SupSize, 1))
    ) trainInfos <- mkTRegFile(
        replicate(Invalid)
    );
    // Each prediction may replace another and we assume the old one to be correct. One more slot for an explicit update.
    Vector#(TAdd#(SupSize, 1), RWire#(UpdateInfo)) updateInfos <- replicateM(mkUnsafeRWire);


    function ActionValue#(GSelectDirPredToken) generatePredictionToken(Integer sup) = actionvalue
        let token = currentPredictionToken[sup];
        currentPredictionToken[sup] <= token + 1;
        return token;
    endactionvalue;

    function GlobalHistory addGlobalHistory(GlobalHistory gh, Result new_item);
        return shiftOutFromN(new_item, gh, 1);
    endfunction
    
    // Get the global history with relevant predictions for previous instructions in this cycle's batch, excluding i.
    function ActionValue#(GlobalHistory) globalHistoryWithBatchHistoryUpTo(Integer i) = actionvalue
        dynamicAssert(i <= valueOf(SupSize), "i must be <= SupSize");
        GlobalHistory globalHistoryWithBatchHistory = globalHistory;
        for (Integer j = 0; j < i; j = j+1)
            if (batchHistory[j].wget() matches tagged Valid .result)
                globalHistoryWithBatchHistory = addGlobalHistory(globalHistoryWithBatchHistory, result);
        return globalHistoryWithBatchHistory;
    endactionvalue;

    rule updateGlobalHistory;
        // Reading all of `batchHistory` causes this rule to be scheduled after all predictions.
        let gh <- globalHistoryWithBatchHistoryUpTo(valueOf(SupSize)); globalHistory <= gh;
    endrule

    for (Integer i = 0; i < valueOf(SupSize) + 1; i = i + 1)
    (* fire_when_enabled *)
    rule doUpdate;
        if (updateInfos[i].wget() matches tagged Valid .updateInfo) begin
            let token = updateInfo.token;
            let maybeActual = updateInfo.actual;
            // Sometimes this method may do nothing (no prediction was made with this token).
            Maybe#(GSelectTrainInfo) maybeTrainInfo = trainInfos.read[i].read(token);
            if (maybeTrainInfo matches tagged Valid .trainInfo) begin
                // mispred used to be given explicitly, this is a way to get it again.
                Bool mispred;
                Result actual;
                if (maybeActual matches tagged Valid .actual_) begin
                    mispred = (actual_ != trainInfo.prediction);
                    actual = actual_;
                end else begin
                    mispred = False;
                    // Deal with implicit updates (old predictions) by assuming we are correct.
                    actual = trainInfo.prediction;
                end

                // Update value with confidence and signal to store it.
                let newVwc = updateValueWithConfidence(
                    predictionTable.read[valueOf(SupSize)+i].read(trainInfo.index),
                    actual
                );
                predictionTable.write[i].write(trainInfo.index, newVwc);

                // Signal deletion of this training info.
                trainInfos.write[valueOf(SupSize)+i].write(token, Invalid);

                if (mispred) begin
                    // Rollback global history to before this prediction then add the correct result. 
                    globalHistory <= addGlobalHistory(trainInfo.globalHistory, actual);
                    // Remove all other training information since the predictions should not have been made.
                    trainInfos.clear;
                end
            end
        end
    endrule

    // Vector to interfaces since Toooba is superscalar.
    // interface Vector#(SupSize, DirPred#(trainInfoT)) pred;
    function DirPred#(GSelectDirPredToken) superscalarPred(Integer sup);
        return (interface DirPred#(GSelectDirPredToken);
            method ActionValue#(DirPredResult#(GSelectDirPredToken)) pred;
                // Get the true PC (minus lower 2 bits and upper bits) for this instruction.
                let pcChopped = pcChoppedBase + fromInteger(sup);

                // Account for previous instructions in superscalar batch.
                GlobalHistory thisGlobalHistory <- globalHistoryWithBatchHistoryUpTo(sup);
                Index index = {pcChopped, pack(thisGlobalHistory)};

                let vwc = predictionTable.read[sup].read(index);
                let prediction = vwc.value;

                // Record that a prediction was made with the result.
                batchHistory[sup].wset(prediction);

                GSelectDirPredToken predictionToken <- generatePredictionToken(sup);
                $display("gselect pred pc=%d, token=%d", pcChopped, predictionToken);
                GSelectTrainInfo trainInfo = GSelectTrainInfo {
                    index: index,
                    prediction: prediction,
                    globalHistory: thisGlobalHistory
                };
                trainInfos.write[sup].write(predictionToken, Valid(trainInfo));
                // Assume we were correct for a possible prediction this entry replaces.
                updateInfos[sup].wset(UpdateInfo {token: predictionToken, actual: Invalid});

                return DirPredResult {
                    taken: prediction,
                    token: predictionToken
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(superscalarPred);

    method Action update(GSelectDirPredToken token, Result actual);
        updateInfos[valueOf(SupSize)].wset(
            UpdateInfo {token: token, actual: Valid(actual)}
        );
    endmethod

    method Action nextPc(Addr pc);
        // Remove the lower 2 bits because instructions are word aligned.
        // Then remove MSBs to fit into NumPcBits.
        pcChoppedBase <= truncate(pc >> 2);
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
