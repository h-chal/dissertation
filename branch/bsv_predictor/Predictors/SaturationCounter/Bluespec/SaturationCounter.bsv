import BrPred::*;
import Vector::*;

import RegFile::*;

export DirPredTrainInfo(..);
export SaturationCounterTrainInfo(..);
export mkSaturationCounter;

export Counter;
export ChoppedAddr;
export NumCounterBits;
export NumPcBits;

// This branch predictor is a generalisation of a bimodal predictor with multiple bits.
// The predictor size is NumCounterBits * 2^NumPcBits.

// The number of bits in each saturating counter.
// 1 <= NumCounterBits.
// When NumCounterBits==2 this is a bimodal predictor.
typedef 2 NumCounterBits;
typedef UInt#(NumCounterBits) Counter;

// The number of bits from the PC to index the table of saturating counters.
// The bits used exclude the two lowest bits of the PC.
// 1 <= NumPcBits <= BrPred::AddrSz - 2.
// 2^NumPcBits is the number of entries.
typedef 12 NumPcBits;
typedef Bit#(NumPcBits) ChoppedAddr;

typedef struct {
    ChoppedAddr pcChopped;
    Counter counter;
} SaturationCounterTrainInfo deriving(Bits, Eq, FShow);
typedef SaturationCounterTrainInfo DirPredTrainInfo;

module mkSaturationCounter(DirPredictor#(SaturationCounterTrainInfo));
    // The lower NumPcBits bits (minus 2 lowest) of the PC for the 0th superscalar fetch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkReg(?);
    RegFile#(ChoppedAddr, Counter) counterTable <- mkRegFileWCF(0, maxBound);

    // Vector to interfaces since Toooba is superscalar.
    function DirPred#(SaturationCounterTrainInfo) superscalarPred(Integer i);
        return (interface DirPred#(SaturationCounterTrainInfo);
            method ActionValue#(DirPredResult#(SaturationCounterTrainInfo)) pred;
                // Get the true PC (minus lower 2 bits and upper bits) for this instruction.
                let pcChopped = pcChoppedBase + fromInteger(i);
                Counter counter = counterTable.sub(pcChopped);
                return DirPredResult {
                    taken: unpack(truncateLSB(pack(counter))),
                    train: SaturationCounterTrainInfo {
                        pcChopped: pcChopped,
                        counter: counter
                    }
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(superscalarPred);

    method Action update(Bool taken, SaturationCounterTrainInfo train, Bool mispred);
        counterTable.upd(
            train.pcChopped,
            taken ? boundedPlus(train.counter, 1) : boundedMinus(train.counter, 1)
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
