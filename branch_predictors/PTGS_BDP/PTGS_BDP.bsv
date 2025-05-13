import BrPred::*;
import PTGS::*;
import ProcTypes::*;
import Types::*;
import Vector::*;

export mkPTGS_BDP;
export PTGS_BdpToken;


typedef UInt#(8) PTGS_BdpToken;

module mkPTGS_BDP(DirPredictor#(PTGS_BdpToken));
    PTGS#(
        Bool,                       // resultT
        PTGS_BdpToken,              // tokenT
        SupSize,                    // numPreds
        4,                          // numPcBits
        8,                          // numGlobalHistoryItems
        Bool,                       // globalHistoryItemT
        1,                          // numConfidenceBits
        0                           // numTagBits
    ) predictor <- mkPTGS(
        'b111100,                   // pcBitMask
        compose(id, validValue)     // globalHistoryItemT makeGlobalHistoryItem(Maybe#(resultT) result)
    );

    function DirPred#(PTGS_BdpToken) genPred(Integer sup);
        return (interface DirPred#(PTGS_BdpToken);
            method ActionValue#(DirPredResult#(PTGS_BdpToken)) pred;
                let result <- predictor.predict[sup].predict;
                return DirPredResult {
                    taken: validValue(result.prediction),  // no tags so never misses so don't need to handle Invalid
                    token: result.token
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(genPred);
    method Action update(PTGS_BdpToken token, Bool taken) = predictor.update(token, Valid(taken));
    method Action nextPc(Addr pc) = predictor.nextPc(pc);
    method Action flush = predictor.flush;
    method Bool flush_done = predictor.flush_done;
endmodule
