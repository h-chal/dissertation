import BtbIfc::*;
import PTGS::*;
import ProcTypes::*;
import Types::*;
import Vector::*;

export mkPTGS_NAP;
export PTGS_NapToken;


typedef UInt#(8) PTGS_NapToken;

module mkPTGS_NAP(NextAddrPred#(PTGS_NapToken));
    PTGS#(
        Bit#(30),                       // resultT              -- major difference from regular Gselect
        PTGS_NapToken,              // tokenT
        SupSizeX2,                  // numPreds
        11,                          // numPcBits
        0,                          // numGlobalHistoryItems
        Bool,                       // globalHistoryItemT
        1,                          // numConfidenceBits
        16                           // numTagBits
    ) predictor <- mkPTGS(
        'b111111111110,                     // pcBitMask
        'b1111111111111111000000000000,     // pcTagBitMask
        isValid                     // globalHistoryItemT makeGlobalHistoryItem(Maybe#(resultT) result)
    );

    Reg#(Addr) pc_reg <- mkRegU;

    function NapPred#(PTGS_NapToken) genPred(Integer sup);
        return (interface NapPred#(PTGS_NapToken);
            method ActionValue#(NapPredResult#(PTGS_NapToken)) pred;
                let result <- predictor.predict[sup].predict;
                return NapPredResult {
                    maybeAddr: isValid(result.prediction) ? Valid({truncateLSB(pc_reg+fromInteger(sup)), validValue(result.prediction)}) : Invalid,
                    token: result.token
                };
            endmethod
        endinterface);
    endfunction
    interface pred = genWith(genPred);
    method Action update(PTGS_NapToken token, Maybe#(Addr) brTarget) = predictor.update(token, isValid(brTarget) ? Valid(truncate(validValue(brTarget))) : Invalid);
    method Action put_pc(Addr pc);
        predictor.nextPc(pc);
        pc_reg <= pc;
    endmethod
    method Action flush = predictor.flush;
    method Bool flush_done = predictor.flush_done;
endmodule
