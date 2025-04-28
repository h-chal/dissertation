import BrPred::*;
import ParamGSelect::*;
import ProcTypes::*;
import Types::*;
import Vector::*;

export mkParamGSelectBdp;
export ParamGSelectBdpToken;


typedef UInt#(8) ParamGSelectBdpToken;

module mkParamGSelectBdp(DirPredictor#(ParamGSelectBdpToken));
    ParamGSelect#(
        Bool,                       // resultT
        ParamGSelectBdpToken,       // tokenT
        SupSize,                    // numPreds
        4,                          // numPcBits
        8,                          // numGlobalHistoryItems
        Bool                        // globalHistoryItemT
    ) predictor <- mkParamGSelect(
        'b111100,                   // pcBitMask
        False,                      // defaultPrediction
        id                          // globalHistoryItemT makeGlobalHistoryItem(resultT result)
    );

    function DirPred#(ParamGSelectBdpToken) genPred(Integer sup);
        return (interface DirPred#(ParamGSelectBdpToken);
            method ActionValue#(DirPredResult#(ParamGSelectBdpToken)) pred;
                let result <- predictor.predict[sup].predict;
                return DirPredResult {
                    taken: result.prediction,
                    token: result.token
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(genPred);
    method Action update(ParamGSelectBdpToken token, Bool taken) = predictor.update(token, taken);
    method Action nextPc(Addr pc) = predictor.nextPc(pc);
    method Action flush = predictor.flush;
    method Bool flush_done = predictor.flush_done;
endmodule
