import BrPred::*;
import Vector::*;

import RegFile::*;

export DirPredTrainInfo(..);
export GSelectTrainInfo(..);
export mkGSelect;

export NumCounterBits;
export Counter;
export NumPcBits;
export ChoppedAddr;
export NumGHistBits;
export GHist;
export NumIndexBits;
export Index;

// This branch predictor uses bits from the PC concatenated with global history to index a table of saturation counters.
// The MSB of a counter gives the prediction.
// The predictor size is NumCounterBits * 2^(NumPcBits+NumGHistBits).

// The number of bits in each saturating counter.
// 1 <= NumCounterBits.
typedef 2 NumCounterBits;
typedef UInt#(NumCounterBits) Counter;

// The number of bits from the PC to index the table of saturating counters.
// The bits used exclude the two lowest bits of the PC.
// 1 <= NumPcBits <= BrPred::AddrSz - 2.
typedef 6 NumPcBits;
typedef Bit#(NumPcBits) ChoppedAddr;

// The number of global branch results to keep.
// 1 <= NumGHistBits.
typedef 6 NumGHistBits;
typedef Bit#(NumGHistBits) GHist;

typedef TAdd#(NumPcBits, NumGHistBits) NumIndexBits;
typedef Bit#(NumIndexBits) Index;

typedef struct {
    Index index;
    Counter counter;
} GSelectTrainInfo deriving(Bits, Eq, FShow);
typedef GSelectTrainInfo DirPredTrainInfo;

module mkGSelect(DirPredictor#(GSelectTrainInfo));
    // The lower NumPcBits bits (minus 2 lowest) of the PC for the 0th superscalar fetch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkReg(?);
    // The global history for conditional branch results (taken/not taken).
    // The MSB is the oldest result.
    Reg#(GHist) gHist <- mkReg(?);

    RegFile#(Index, Counter) counterTable <- mkRegFileWCF(0, maxBound);

    // Vector to interfaces since Toooba is superscalar.
    function DirPred#(GSelectTrainInfo) superscalarPred(Integer i);
        return (interface DirPred#(GSelectTrainInfo);
            method ActionValue#(DirPredResult#(GSelectTrainInfo)) pred;
                // Get the true PC (minus lower 2 bits and upper bits) for this instruction.
                let pcChopped = pcChoppedBase + fromInteger(i);
                Index index = {pcChopped, gHist};
                Counter counter = counterTable.sub(index);
                return DirPredResult {
                    // The MSB of a counter gives the prediction.
                    taken: unpack(truncateLSB(pack(counter))),
                    train: GSelectTrainInfo {
                        index: index,
                        counter: counter
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
        gHist <= (gHist << 1) + extend(pack(taken));
    endmethod

    method Action nextPc(Addr pc);
        // Remove the lower 2 bits because instructions are word aligned.
        // Then remove MSBs to fit into NumPcBits.
        pcChoppedBase <= truncate(pc >> 2);
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
