import BrPred::*;

import Vector::*;
import RegFile::*;
import Assert::*;

export DirPredTrainInfo(..);
export GSelectTrainInfo(..);
export mkGSelect;

export NumCounterBits;
export Counter;
export NumPcBits;
export ChoppedAddr;
export NumGlobalHistoryBits;
export GlobalHistory;
export NumIndexBits;
export Index;

// This branch predictor uses bits from the PC concatenated with global history to index a table of saturation counters.
// The MSB of a counter gives the prediction.
// The predictor size is NumCounterBits * 2^(NumPcBits+NumGlobalHistoryBits).

// The number of bits in each saturating counter.
// 1 <= NumCounterBits.
typedef 2 NumCounterBits;
typedef UInt#(NumCounterBits) Counter;

// The number of bits from the PC to index the table of saturating counters.
// The bits used exclude the two lowest bits of the PC.
// 1 <= NumPcBits <= BrPred::AddrSz - 2.
typedef 4 NumPcBits;
typedef Bit#(NumPcBits) ChoppedAddr;

// The number of global branch results to keep.
// 1 <= NumGlobalHistoryBits.
typedef 8 NumGlobalHistoryBits;
typedef Bit#(NumGlobalHistoryBits) GlobalHistory;

typedef TAdd#(NumPcBits, NumGlobalHistoryBits) NumIndexBits;
typedef Bit#(NumIndexBits) Index;

typedef struct {
    Index index;
    Counter counter;
    GlobalHistory globalHistory;
} GSelectTrainInfo deriving(Bits, Eq, FShow);
typedef GSelectTrainInfo DirPredTrainInfo;

module mkGSelect(DirPredictor#(GSelectTrainInfo));
    staticAssert(1 <= valueOf(NumCounterBits), "Must have 1 <= NumCounterBits");
    staticAssert(1 <= valueOf(NumPcBits) && valueOf(NumPcBits) <= valueOf(AddrSz) - 2, "Must have 1 <= NumPcBits <= AddrSz - 2");
    staticAssert(1 <= valueOf(NumGlobalHistoryBits), "Must have 1 <= NumGlobalHistoryBits");


    // The lower `NumPcBits` bits (minus 2 lowest) of the PC for first instruction in the superscalar batch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkRegU;
    // The global history of conditional branch results (taken/not taken). The MSB is the oldest result.
    Reg#(GlobalHistory) globalHistory <- mkRegU;
    RegFile#(Index, Counter) counterTable <- mkRegFileWCF(0, maxBound);
    // Registers to store the global history for this superscalar batch.
    Vector#(SupSize,RWire#(Bool)) batchHistory <- replicateM(mkRWire);
    
    // Get the global history with relevant predictions for previous instructions in this cycle's batch, excluding i.
    function ActionValue#(GlobalHistory) globalHistoryWithBatchHistoryUpTo(Integer i) = actionvalue
        dynamicAssert(i <= valueOf(SupSize), "i must be <= SupSize");
        GlobalHistory globalHistoryWithBatchHistory = globalHistory;
        for (Integer j = 0; j < i; j = j+1)
            if (batchHistory[j].wget() matches tagged Valid .taken)
                globalHistoryWithBatchHistory = {truncate(globalHistoryWithBatchHistory), pack(taken)};
        return globalHistoryWithBatchHistory;
    endactionvalue;

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
                Index index = {pcChopped, thisGlobalHistory};

                Counter counter = counterTable.sub(index);
                // The MSB of a counter gives the prediction.
                Bool taken = unpack(truncateLSB(pack(counter)));

                // Record that a prediction was made with the result.
                batchHistory[fromInteger(i)].wset(taken);
                return DirPredResult {
                    taken: taken,
                    train: GSelectTrainInfo {
                        index: index,
                        counter: counter,
                        globalHistory: thisGlobalHistory
                    }
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(superscalarPred);

    method Action update(Bool taken, GSelectTrainInfo train, Bool mispred);
        counterTable.upd(
            train.index,
            taken ? boundedPlus(train.counter, 1) : boundedMinus(train.counter, 1)
        );
        if (mispred)
            globalHistory <= {truncate(train.globalHistory), pack(taken)};
    endmethod

    method Action nextPc(Addr pc);
        // Remove the lower 2 bits because instructions are word aligned.
        // Then remove MSBs to fit into NumPcBits.
        pcChoppedBase <= truncate(pc >> 2);
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
