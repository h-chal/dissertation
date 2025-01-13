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

// When NumCounterBits==2 this is a bimodal predictor.
// NumCounterBits should be at least 1.
typedef 4 NumCounterBits;
typedef UInt#(NumCounterBits) Counter;

// NumPcBits should not be greater than BrPred::AddrSz and should be at least 1.
// 2^NumPcBits is the number of entries.
// The predictor size is NumCounterBits * 2^NumPcBits.
typedef 12 NumPcBits;
typedef Bit#(NumPcBits) ChoppedAddr;

typedef struct {
    Counter counter;
    ChoppedAddr pcChopped;
} SaturationCounterTrainInfo deriving(Bits, Eq, FShow);
typedef SaturationCounterTrainInfo DirPredTrainInfo;

module mkSaturationCounter(DirPredictor#(SaturationCounterTrainInfo));
    // The first NumPcBits bits of the program counter for the 0th superscalar fetch.
    Reg#(ChoppedAddr) pcChoppedBase <- mkReg(?);
    RegFile#(ChoppedAddr, Counter) counterTable <- mkRegFileWCF(0, maxBound);

    // Vector to interfaces since Toooba is superscalar.
    function DirPred#(SaturationCounterTrainInfo) superscalarPred(Integer i);
        return (interface DirPred#(SaturationCounterTrainInfo);
            method ActionValue#(DirPredResult#(SaturationCounterTrainInfo)) pred;
                let pcChopped = pcChoppedBase + fromInteger(i);
                Counter counter = counterTable.sub(pcChopped);
                return DirPredResult {
                    taken: unpack(truncateLSB(pack(counter))),
                    train: SaturationCounterTrainInfo {
                        counter: counter,
                        pcChopped: pcChopped
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
        pcChoppedBase <= truncateLSB(pc);
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
