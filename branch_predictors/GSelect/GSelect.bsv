`ifdef USING_TOOOBA
import Types::*;
import ProcTypes::*;
`endif
import BrPred::*;
import Ehr::*;

import Vector::*;
import RegFile::*;
import Assert::*;

export GSelectDirPredToken;
export mkGSelect;


// This branch predictor uses bits from the PC concatenated with global history to index a table of saturation counters.
// Booleans with a 1-bit counter (ValueWithHysteresis) is used in place of 2-bit saturating counters.
// The predictor size is NumCounterBits * 2^(NumPcBits+(NumGlobalHistoryItems*SizeOf(Result)).

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


module mkGSelect(DirPredictor#(GSelectDirPredToken));
    staticAssert(1 <= valueOf(NumCounterBits), "Must have 1 <= NumCounterBits");
    staticAssert(1 <= valueOf(NumPcBits) && valueOf(NumPcBits) <= valueOf(AddrSz) - 2, "Must have 1 <= NumPcBits <= AddrSz - 2");
    staticAssert(1 <= valueOf(NumGlobalHistoryItems), "Must have 1 <= NumGlobalHistoryItems");


    // The lower `NumPcBits` bits (minus 2 lowest) of the PC for first instruction in the superscalar batch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkRegU;
    // The global history of conditional branch results (taken/not taken). The MSB is the oldest result.
    Reg#(GlobalHistory) globalHistory <- mkRegU;
    Vector#(TExp#(NumIndexBits), Reg#(ValueWithHysteresis)) predictionTable <- replicateM(mkRegU);
    Vector#(TAdd#(SupSize, 1), RWire#(Tuple2#(Index, ValueWithHysteresis))) predictionTableWriters <- replicateM(mkRWire);
    // Registers to store the global history for this superscalar batch.
    Vector#(SupSize, RWire#(Result)) batchHistory <- replicateM(mkUnsafeRWire);
    Ehr#(SupSize, GSelectDirPredToken) currentPredictionToken <- mkEhr(0);
    Vector#(NumPastPreds, Reg#(Maybe#(GSelectTrainInfo))) trainInfos <- replicateM(mkReg(Invalid));
    Vector#(TAdd#(TMul#(SupSize, 2), 1), RWire#(Tuple2#(GSelectDirPredToken, Maybe#(GSelectTrainInfo)))) trainInfosWriters <- replicateM(mkRWire);
    PulseWire process_mispred <- mkPulseWireOR();
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
            Maybe#(GSelectTrainInfo) maybeTrainInfo = readReg(trainInfos[token]);
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
                let newVwh = updateValueWithHysteresis(trainInfo.vwh, actual);
                predictionTableWriters[i].wset(tuple2(trainInfo.index, newVwh));

                // Signal deletion of this training info.
                trainInfosWriters[valueOf(SupSize)+i].wset(tuple2(token, Invalid));

                if (mispred) begin
                    // Rollback global history to before this prediction then add the correct result. 
                    globalHistory <= addGlobalHistory(trainInfo.globalHistory, actual);
                    // Remove all other training information since the predictions should not have been made.
                    process_mispred.send();
                end
            end
        end
    endrule

    for (Index i = 0; i < maxBound; i = i + 1)
        (* fire_when_enabled *)
        rule writePredictionTable;
            Bool done = False;
            for (Integer w = 0; w < valueOf(SupSize) + 1 && !done; w = w + 1)
                if (predictionTableWriters[w].wget() matches tagged Valid {.writeIndex, .vwh})
                    // I don't think I can pattern match an Index.
                    if (writeIndex == i) begin
                        done = True;
                        writeReg(predictionTable[i], vwh);
                    end
        endrule

    for (GSelectDirPredToken i = 0; i < maxBound; i = i + 1)
        (* fire_when_enabled *)
        rule writeTrainInfo;
            Bool done = False;
            for (Integer w = 0; w < 2*valueOf(SupSize)+1 && !done; w = w + 1)
                if (trainInfosWriters[w].wget() matches tagged Valid {.writePredictionToken, .trainInfo})
                    // I don't think I can pattern match an Index.
                    if (writePredictionToken == i) begin
                        done = True;
                        writeReg(trainInfos[i], trainInfo);
                    end
        endrule

    (* fire_when_enabled *)
    rule removeTrainInfos(process_mispred);
        writeVReg(trainInfos, replicate(Invalid));
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

                ValueWithHysteresis vwh = readReg(predictionTable[index]);

                // Record that a prediction was made with the result.
                batchHistory[sup].wset(vwh.value);

                GSelectDirPredToken predictionToken <- generatePredictionToken(sup);
                $display("gselect pred pc=%d, token=%d", pcChopped, predictionToken);
                GSelectTrainInfo trainInfo = GSelectTrainInfo {
                    index: index,
                    vwh: vwh,
                    globalHistory: thisGlobalHistory
                };
                trainInfosWriters[sup].wset(tuple2(predictionToken, Valid(trainInfo)));
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
