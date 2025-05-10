import BtbIfc::*;
import ParamGSelect::*;
import ProcTypes::*;
import Types::*;
import Vector::*;

export mkParamGSelectNap;
export ParamGSelectNapToken;


typedef UInt#(8) ParamGSelectNapToken;

module mkParamGSelectNap(NextAddrPred#(ParamGSelectNapToken));
    ParamGSelect#(
        Maybe#(Addr),               // resultT
        ParamGSelectNapToken,       // tokenT
        SupSizeX2,                  // numPreds
        3,                          // numPcBits
        7,                          // numGlobalHistoryItems
        Bool,                       // globalHistoryItemT
        1                           // numConfidenceBits
    ) predictor <- mkParamGSelect(
        'b1110,                    // pcBitMask
        Invalid,                    // defaultPrediction
        isValid                     // globalHistoryItemT makeGlobalHistoryItem(resultT result)
    );

    function NapPred#(ParamGSelectNapToken) genPred(Integer sup);
        return (interface NapPred#(ParamGSelectNAPToken);
            method ActionValue#(NapPredResult#(ParamGSelectNapToken)) pred;
                let result <- predictor.predict[sup].predict;
                return NapPredResult {
                    maybeAddr: result.prediction,
                    token: result.token
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(genPred);
    method Action update(ParamGSelectNapToken token, Maybe#(Addr) brTarget) = predictor.update(token, brTarget);
    method Action put_pc(Addr pc) = predictor.nextPc(pc);
    method Action flush = predictor.flush;
    method Bool flush_done = predictor.flush_done;
endmodule
