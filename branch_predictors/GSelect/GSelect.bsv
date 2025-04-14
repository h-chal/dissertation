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

export GSelectDirPredToken;
export mkGSelect;


// This branch predictor uses bits from the PC concatenated with global history to index a table of saturation counters.
// Booleans with a 1-bit counter (ValueWithHysteresis) is used in place of 2-bit saturating counters.
// The predictor size is NumCounterBits * 2^(NumPcBits+(NumGlobalHistoryItems*SizeOf(Result)).


// For ease of reading, assume HCHAL_OPTIMISED_COMPILE is not defined.
`include "OptimisedCompileSettings.bsv"
`ifdef HCHAL_OPTIMISED_COMPILE
    import OptimisedCompile::*;
`endif


// A Boolean value for whether a branch should be (or was) taken.
typedef Bool Result;

// The number of hysteresis bits in each saturating counter.
// 1 <= NumCounterBits.
typedef 1 NumCounterBits;
typedef struct {
    Result value;
    UInt#(NumCounterBits) hysteresis;
} ValueWithHysteresis deriving(Bits, Eq, FShow);

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
    ValueWithHysteresis vwh;
    GlobalHistory globalHistory;
} GSelectTrainInfo deriving(Bits, Eq, FShow);

typedef struct {
    GSelectDirPredToken token;
    Maybe#(Result) actual;  // Valid if explicit update, Invalid if implicit update.
} UpdateInfo deriving(Bits);


module [Module] mkGSelect(DirPredictor#(GSelectDirPredToken));
    
    // The lower `NumPcBits` bits (minus 2 lowest) of the PC for first instruction in the superscalar batch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkRegU;
    // The global history of conditional branch results (taken/not taken). The MSB is the oldest result.
    Reg#(GlobalHistory) globalHistory <- mkRegU;
    // Registers to store the global history for this superscalar batch.
    Vector#(SupSize, RWire#(Result)) batchHistory <- replicateM(mkUnsafeRWire);
    Ehr#(SupSize, GSelectDirPredToken) currentPredictionToken <- mkEhr(0);
    // Each prediction may replace another and we assume the old one to be correct. One more slot for an explicit update.
    Vector#(TAdd#(SupSize, 1), RWire#(UpdateInfo)) updateInfos <- replicateM(mkUnsafeRWire);

`ifndef HCHAL_OPTIMISED_COMPILE
    TRegFile#(
        Index, ValueWithHysteresis, TAdd#(SupSize, 1)
    ) predictionTable <- mkTRegFile(
        replicate(ValueWithHysteresis {value: False, hysteresis: 0})
    );
    TRegFile#(
        GSelectDirPredToken,
        Maybe#(GSelectTrainInfo),
        TAdd#(TMul#(SupSize, 2), 1)
    ) trainInfos <- mkTRegFile(replicate(Invalid));
`else
    TRegFile#(
        Opt_GSelect_Index, Opt_GSelect_ValueWithHysteresis, TAdd#(SupSize, 1)
    ) predictionTable <- mkOptimisedGSelectPredictionTable;
    TRegFile#(
        Opt_GSelect_GSelectDirPredToken,
        Maybe#(Opt_GSelect_GSelectTrainInfo),
        TAdd#(TMul#(SupSize, 2), 1)
    ) trainInfos <- mkOptimisedGSelectTrainInfos;
`endif


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

    function ValueWithHysteresis updateValueWithHysteresis(ValueWithHysteresis vwh, Result new_value);
        if (vwh.value == new_value)
            return ValueWithHysteresis {
                value: vwh.value,
                hysteresis: boundedPlus(vwh.hysteresis, 1)
            };
        else begin
            if (vwh.hysteresis > 0)
                return ValueWithHysteresis {
                    value: vwh.value,
                    hysteresis: vwh.hysteresis - 1
                };
            else
                return ValueWithHysteresis {
                    value: new_value,
                    hysteresis: 0
                };
        end
    endfunction

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
`ifndef HCHAL_OPTIMISED_COMPILE
            Maybe#(GSelectTrainInfo) maybeTrainInfo = trainInfos.read[token];
`else
            Opt_GSelect_GSelectDirPredToken opt_token = token;
            let opt_maybeTrainInfo = trainInfos.read[opt_token];
            Maybe#(GSelectTrainInfo) maybeTrainInfo = unpack(pack(opt_maybeTrainInfo));
`endif
            if (maybeTrainInfo matches tagged Valid .trainInfo) begin
                // mispred used to be given explicitly, this is a way to get it again.
                Bool mispred;
                Result actual;
                if (maybeActual matches tagged Valid .actual_) begin
                    mispred = (actual_ != trainInfo.vwh.value);
                    actual = actual_;
                end else begin
                    mispred = False;
                    // Deal with implicit updates (old predictions) by assuming we are correct.
                    actual = trainInfo.vwh.value;
                end

                // Update value with hysteresis and signal to store it.
`ifndef HCHAL_OPTIMISED_COMPILE
                let newVwh = updateValueWithHysteresis(predictionTable.read[trainInfo.index], actual);
                predictionTable.write[i] <= tuple2(trainInfo.index, newVwh);
`else
                Opt_GSelect_Index opt_index = trainInfo.index;
                let opt_oldVwh = predictionTable.read[opt_index];
                ValueWithHysteresis oldVwh = unpack(pack(opt_oldVwh));
                let newVwh = updateValueWithHysteresis(oldVwh, actual);
                Opt_GSelect_ValueWithHysteresis opt_newVwh = unpack(pack(newVwh));
                predictionTable.write[i] <= tuple2(opt_index, opt_newVwh);
`endif

                // Signal deletion of this training info.
`ifndef HCHAL_OPTIMISED_COMPILE
                trainInfos.write[valueOf(SupSize)+i] <= tuple2(token, Invalid);
`else
                Opt_GSelect_GSelectDirPredToken opt_token = token;
                trainInfos.write[valueOf(SupSize)+i] <= tuple2(opt_token, Invalid);
`endif

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
`ifndef HCHAL_OPTIMISED_COMPILE
                ValueWithHysteresis vwh = predictionTable.read[index];
`else
                let opt_vwh = predictionTable.read[index];
                ValueWithHysteresis vwh = unpack(pack(opt_vwh));
`endif

                // Record that a prediction was made with the result.
                batchHistory[sup].wset(vwh.value);

                GSelectDirPredToken predictionToken <- generatePredictionToken(sup);
                $display("gselect pred pc=%d, token=%d", pcChopped, predictionToken);
                GSelectTrainInfo trainInfo = GSelectTrainInfo {
                    index: index,
                    vwh: vwh,
                    globalHistory: thisGlobalHistory
                };
`ifndef HCHAL_OPTIMISED_COMPILE
                trainInfos.write[sup] <= tuple2(predictionToken, Valid(trainInfo));
`else
                Opt_GSelect_GSelectDirPredToken opt_predictionToken = predictionToken;
                Maybe#(Opt_GSelect_GSelectTrainInfo) opt_validTrainInfo = 
                    unpack(pack(Valid(trainInfo)));
                trainInfos.write[sup] <= tuple2(opt_predictionToken, opt_validTrainInfo);
`endif
                // Assume we were correct for a possible prediction this entry replaces.
                updateInfos[sup].wset(UpdateInfo {token: predictionToken, actual: Invalid});

                return DirPredResult {
                    taken: vwh.value,
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
