import BrPred::*;
import Vector::*;

export DirPredTrainInfo(..);
export AlwaysTakenTrainInfo(..);
export mkAlwaysTaken;

// This will be a struct for more complicated predictors.
typedef Bit#(0) AlwaysTakenTrainInfo;// deriving(Bits, Eq, FShow);
typedef AlwaysTakenTrainInfo DirPredTrainInfo;

module mkAlwaysTaken(DirPredictor#(AlwaysTakenTrainInfo));
    interface pred = replicate(interface DirPred;
        method ActionValue#(DirPredResult#(AlwaysTakenTrainInfo)) pred;
            return DirPredResult {
                taken: True,
                // Pred interface(s) must propagate info used for update.
                train: ?
            };
        endmethod
    endinterface);

    // Empty methods that must be defined.
    method Action update(Bool taken, AlwaysTakenTrainInfo train, Bool mispred) = noAction;
    method Action nextPc(Addr pc) = noAction;
    method flush = noAction;
    method flush_done = True;
endmodule