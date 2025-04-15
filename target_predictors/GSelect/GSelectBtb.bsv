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

export GSelectBtbToken;
export mkGSelectBtb;

export NextAddrPred(..);
export BtbResult(..);
export BtbPred(..);

interface BtbPred#(type btbTokenT);
    method ActionValue#(BtbResult#(btbTokenT)) pred;
endinterface

interface NextAddrPred#(type btbTokenT);
    //method Action put_pc(Addr pc);
    method Action nextPc(Addr pc);
    interface Vector#(SupSizeX2, BtbPred#(btbTokenT)) pred;
    method Action update(btbTokenT token, Maybe#(Addr) brTarget);
    // security
    method Action flush;
    method Bool flush_done;
endinterface

typedef struct {
    Maybe#(Addr) maybeAddr;
    btbTokenT token; // info for future training
} BtbResult#(type btbTokenT) deriving(Bits, Eq, FShow);


// This BTB uses bits from the PC concatenated with global history to index a table of saturation counters.
// Booleans with a 1-bit counter (ValueWithHysteresis) is used in place of 2-bit saturating counters.
// The predictor size is NumCounterBits * 2^(NumPcBits+(NumGlobalHistoryItems*SizeOf(Result)).

// Valid(target) for a branch/jump to target, or Invalid for continuing to PC+2.
typedef Maybe#(Addr) Result;

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
typedef Vector#(NumGlobalHistoryItems, Bool) GlobalHistory;

typedef TAdd#(NumPcBits, NumGlobalHistoryItems) NumIndexBits;
typedef Bit#(NumIndexBits) Index;

typedef UInt#(8) GSelectBtbToken;
typedef TExp#(SizeOf#(GSelectBtbToken)) NumPastPreds;

typedef struct {
    Index index;
    ValueWithHysteresis vwh;
    GlobalHistory globalHistory;
} GSelectTrainInfo deriving(Bits, Eq, FShow);

typedef struct {
    GSelectBtbToken token;
    Maybe#(Result) actual; // Valid if explicit update, Invalid if implicit update.
} UpdateInfo deriving(Bits);


module mkGSelectBtb(NextAddrPred#(GSelectBtbToken));
    staticAssert(1 <= valueOf(NumCounterBits), "Must have 1 <= NumCounterBits");
    staticAssert(1 <= valueOf(NumPcBits) && valueOf(NumPcBits) <= valueOf(AddrSz) - 2, "Must have 1 <= NumPcBits <= AddrSz - 2");
    staticAssert(1 <= valueOf(NumGlobalHistoryItems), "Must have 1 <= NumGlobalHistoryItems");


    // The lower `NumPcBits` bits (minus lowest) of the PC for first instruction in the superscalar batch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkRegU;
    // The global history of conditional branch results (taken/not taken). The MSB is the oldest result.
    Reg#(GlobalHistory) globalHistory <- mkRegU;
    TRegFile#(
        Index,
        ValueWithHysteresis,
        TAdd#(SupSizeX2, TAdd#(SupSizeX2, 1)),
        TAdd#(SupSizeX2, 1)
    ) predictionTable <- mkTRegFile(
        replicate(ValueWithHysteresis {value: Invalid, hysteresis: 0})
    );
    // Registers to store the global history for this superscalar batch.
    Vector#(SupSizeX2, RWire#(Bool)) batchHistory <- replicateM(mkUnsafeRWire);
    Ehr#(SupSizeX2, GSelectBtbToken) currentPredictionToken <- mkEhr(0);
    TRegFile#(
        GSelectBtbToken,
        Maybe#(GSelectTrainInfo),
        TAdd#(SupSizeX2, 1),
        TAdd#(SupSizeX2, TAdd#(SupSizeX2, 1))
    ) trainInfos <- mkTRegFile(
        replicate(Invalid)
    );
    // Each prediction may replace another and we assume the old one to be correct. One more slot for an explicit update.
    Vector#(TAdd#(SupSizeX2, 1), RWire#(UpdateInfo)) updateInfos <- replicateM(mkUnsafeRWire);


    function ActionValue#(GSelectBtbToken) generatePredictionToken(Integer sup) = actionvalue
        let token = currentPredictionToken[sup];
        currentPredictionToken[sup] <= token + 1;
        return token;
    endactionvalue;

    function GlobalHistory addGlobalHistory(GlobalHistory gh, Bool new_item);
        return shiftOutFromN(new_item, gh, 1);
    endfunction
    
    // Get the global history with relevant predictions for previous instructions in this cycle's batch, excluding i.
    function ActionValue#(GlobalHistory) globalHistoryWithBatchHistoryUpTo(Integer i) = actionvalue
        dynamicAssert(i <= valueOf(SupSizeX2), "i must be <= SupSizeX2");
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
        let gh <- globalHistoryWithBatchHistoryUpTo(valueOf(SupSizeX2)); globalHistory <= gh;
    endrule

    for (Integer i = 0; i < valueOf(SupSizeX2) + 1; i = i + 1)
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
                    mispred = (actual_ != trainInfo.vwh.value);
                    actual = actual_;
                end else begin
                    mispred = False;
                    // Deal with implicit updates (old predictions) by assuming we are correct.
                    actual = trainInfo.vwh.value;
                end

                // Update value with hysteresis and signal to store it.
                let newVwh = updateValueWithHysteresis(
                    predictionTable.read[valueOf(SupSizeX2)+i].read(trainInfo.index),
                    actual
                );
                predictionTable.write[i].write(trainInfo.index, newVwh);

                // Signal deletion of this training info.
                trainInfos.write[valueOf(SupSizeX2)+i].write(token, Invalid);

                if (mispred) begin
                    // Rollback global history to before this prediction then add the correct result.
                    Bool v = False;
                    if (actual matches tagged Valid .*)
                        v = True;
                    globalHistory <= addGlobalHistory(trainInfo.globalHistory, v);
                    // Remove all other training information since the predictions should not have been made.
                    trainInfos.clear;
                end
            end
        end
    endrule

    // Vector to interfaces since Toooba is superscalar.
    // interface Vector#(SupSizeX2, BtbPred#(trainInfoT)) pred;
    function BtbPred#(GSelectBtbToken) superscalarPred(Integer sup);
        return (interface BtbPred#(GSelectBtbToken);
            method ActionValue#(BtbResult#(GSelectBtbToken)) pred;
                // Get the true PC (minus 1 lower bit and upper bits) for this instruction.
                let pcChopped = pcChoppedBase + fromInteger(sup);

                // Account for previous instructions in superscalar batch.
                GlobalHistory thisGlobalHistory <- globalHistoryWithBatchHistoryUpTo(sup);
                Index index = {pcChopped, pack(thisGlobalHistory)};
                ValueWithHysteresis vwh = predictionTable.read[sup].read(index);

                // Record that a prediction was made with the result.
                Bool v = False;
                if (vwh.value matches tagged Valid .*)
                    v = True;
                batchHistory[sup].wset(v);

                GSelectBtbToken predictionToken <- generatePredictionToken(sup);
                $display("gselect pred pc=%d, token=%d", pcChopped, predictionToken);
                GSelectTrainInfo trainInfo = GSelectTrainInfo {
                    index: index,
                    vwh: vwh,
                    globalHistory: thisGlobalHistory
                };
                trainInfos.write[sup].write(predictionToken, Valid(trainInfo));
                // Assume we were correct for a possible prediction this entry replaces.
                updateInfos[sup].wset(UpdateInfo {token: predictionToken, actual: Invalid});

                return BtbResult {
                    maybeAddr: vwh.value,
                    token: predictionToken
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(superscalarPred);

    method Action update(GSelectBtbToken token, Result actual);
        updateInfos[valueOf(SupSizeX2)].wset(
            UpdateInfo {token: token, actual: Valid(actual)}
        );
    endmethod

    method Action nextPc(Addr pc);
        // Remove a lower bit because instruction fragments are half-word aligned.
        // Then remove MSBs to fit into NumPcBits.
        pcChoppedBase <= truncate(pc >> 1);
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
