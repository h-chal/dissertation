`ifdef USING_TOOOBA
import Types::*;
import ProcTypes::*;
`endif
import BrPred::*;


import Vector::*;
import RegFile::*;
import Assert::*;

export DirPredTrainInfo(..);
export GSelectTrainInfo(..);
export mkGSelect;

export Result;
export NumCounterBits;
export ValueWithHysteresis;
export NumPcBits;
export ChoppedAddr;
export NumGlobalHistoryItems;
export GlobalHistory;
export NumIndexBits;
export Index;

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

typedef struct {
    Index index;
    ValueWithHysteresis vwh;
    GlobalHistory globalHistory;
} GSelectTrainInfo deriving(Bits, Eq, FShow);
typedef GSelectTrainInfo DirPredTrainInfo;


module mkGSelect(DirPredictor#(GSelectTrainInfo));
    staticAssert(1 <= valueOf(NumCounterBits), "Must have 1 <= NumCounterBits");
    staticAssert(1 <= valueOf(NumPcBits) && valueOf(NumPcBits) <= valueOf(AddrSz) - 2, "Must have 1 <= NumPcBits <= AddrSz - 2");
    staticAssert(1 <= valueOf(NumGlobalHistoryItems), "Must have 1 <= NumGlobalHistoryItems");


    // The lower `NumPcBits` bits (minus 2 lowest) of the PC for first instruction in the superscalar batch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkRegU;
    // The global history of conditional branch results (taken/not taken). The MSB is the oldest result.
    Reg#(GlobalHistory) globalHistory <- mkRegU;
    RegFile#(Index, ValueWithHysteresis) predictionTable <- mkRegFileWCF(0, maxBound);
    // Registers to store the global history for this superscalar batch.
    Vector#(SupSize, RWire#(Bool)) batchHistory <- replicateM(mkUnsafeRWire);

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

    // Vector to interfaces since Toooba is superscalar.
    // interface Vector#(SupSize, DirPred#(trainInfoT)) pred;
    function DirPred#(GSelectTrainInfo) superscalarPred(Integer i);
        return (interface DirPred#(GSelectTrainInfo);
            method ActionValue#(DirPredResult#(GSelectTrainInfo)) pred;
                // Get the true PC (minus lower 2 bits and upper bits) for this instruction.
                let pcChopped = pcChoppedBase + fromInteger(i);
                // Account for previous instructions in superscalar batch.
                GlobalHistory thisGlobalHistory <- globalHistoryWithBatchHistoryUpTo(i);
                Index index = {pcChopped, pack(thisGlobalHistory)};

                ValueWithHysteresis vwh = predictionTable.sub(index);

                // Record that a prediction was made with the result.
                batchHistory[fromInteger(i)].wset(vwh.value);
                return DirPredResult {
                    taken: vwh.value,
                    train: GSelectTrainInfo {
                        index: index,
                        vwh: vwh,
                        globalHistory: thisGlobalHistory
                    }
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(superscalarPred);

    method Action update(Bool taken, GSelectTrainInfo train, Bool mispred);
        predictionTable.upd(
            train.index,
            updateValueWithHysteresis(train.vwh, taken)
        );
        if (mispred)
            // Rollback global history to before this prediction then add the correct result. 
            globalHistory <= addGlobalHistory(train.globalHistory, taken);
    endmethod

    method Action nextPc(Addr pc);
        // Remove the lower 2 bits because instructions are word aligned.
        // Then remove MSBs to fit into NumPcBits.
        pcChoppedBase <= truncate(pc >> 2);
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
