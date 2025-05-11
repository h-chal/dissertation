// Partially tagged Gselect

import ISA_Decls::*;
import Types::*;

import Ehr::*;
import Vector::*;
import RegFile::*;
import Assert::*;
import TRegFile::*;
import ValueWithConfidence::*;

export PTGS(..);
export Predict(..);
export PredictResult(..);
export mkPTGS;


typedef struct {
    tokenT token;
    Maybe#(resultT) prediction;
} PredictResult#(type tokenT, type resultT) deriving(Bits, Eq, FShow);

interface Predict#(type tokenT, type resultT);
    method ActionValue#(PredictResult#(tokenT, resultT)) predict;
endinterface

interface PTGS#(
    type resultT,
    type tokenT,
    numeric type numPreds,
    numeric type numPcBits,
    numeric type numGlobalHistoryItems,
    type globalHistoryItemT,
    numeric type numConfidenceBits,
    numeric type numTagBits
);
    method Action nextPc(Addr nextPc);
    interface Vector#(numPreds, Predict#(tokenT, resultT)) predict;
    method Action update(tokenT token, Maybe#(resultT) actual);
    method Action flush;
    method Bool flush_done;
endinterface


typedef struct {
    indexT index;
    Maybe#(resultT) prediction;
    globalHistoryT globalHistory;  // Some redundancy with index.
    Bit#(numTagBits) tag;
} TrainInfo#(type indexT, type resultT, type globalHistoryT, numeric type numTagBits) deriving(Bits, Eq, FShow);

typedef struct {
    tokenT token;
    Maybe#(Maybe#(resultT)) actual;  // Valid if explicit update, Invalid if implicit update -- then Valid if should hit, Invalid if should miss
} UpdateInfo#(type tokenT, type resultT) deriving(Bits);

typedef struct {
    Maybe#(ValueWithConfidence#(resultT, numConfidenceBits)) m_vwc;  // "Maybe" allows deletion of entries (validity).
    Bit#(numTagBits) tag;
} PredictionTableEntry#(type resultT, numeric type numConfidenceBits, numeric type numTagBits) deriving(Bits);

function Bit#(numBits) extractMask(Addr mask, Addr in);
    Bit#(numBits) maskedPc = 0;
    Integer outIndex = 0;
    for (Integer i = 0; i < valueOf(XLEN); i = i + 1)
        if (mask[i] == 1) begin
            maskedPc[outIndex] = in[i];
            outIndex = outIndex + 1;
        end
    return maskedPc;
endfunction


module mkPTGS#(
    Addr pcBitMask,  // Must have numPcBits set bits.
    Addr pcTagBitMask,
    function globalHistoryItemT makeGlobalHistoryItem(Maybe#(resultT) result)  // Which bits of the result to remember for global history.
) (PTGS#(resultT, tokenT, numPreds, numPcBits, numGlobalHistoryItems, globalHistoryItemT, numConfidenceBits, numTagBits))
    provisos(
        Alias#(choppedAddr, Bit#(numPcBits)),
        Alias#(globalHistoryT, Vector#(numGlobalHistoryItems, globalHistoryItemT)),
        Alias#(index, Bit#(TAdd#(numPcBits, TMul#(numGlobalHistoryItems, SizeOf#(globalHistoryItemT))))),

        Eq#(resultT),
        Bits#(resultT, resultSz),
        Bits#(tokenT, tokenSz),
        Ord#(tokenT),
        PrimIndex#(tokenT, tokenEntries),
        Arith#(tokenT)
    );

    staticAssert(fromInteger(valueOf(numPcBits)) == countOnes(pcBitMask), "pcBitMask must have numPcBits bits.");

    Reg#(Addr) pcReg <- mkRegU;
    // The global history of previous results, including predictions.
    Reg#(globalHistoryT) globalHistory <- mkRegU;
    TRegFile#(
        index,
        PredictionTableEntry#(resultT, numConfidenceBits, numTagBits),
        TAdd#(numPreds, TAdd#(numPreds, 1)),
        TAdd#(numPreds, 1)
    ) predictionTable <- mkTRegFile(replicate(
        PredictionTableEntry {
            m_vwc: Invalid,
            tag: ?
        }
    ));
    // Registers to store the global history for this superscalar batch.
    Vector#(numPreds, RWire#(Maybe#(resultT))) batchHistory <- replicateM(mkUnsafeRWire);
    Ehr#(numPreds, tokenT) currentPredictionToken <- mkEhr(0);
    TRegFile#(
        tokenT,
        Maybe#(TrainInfo#(index, resultT, globalHistoryT, numTagBits)),
        TAdd#(numPreds, 1),
        TAdd#(numPreds, TAdd#(numPreds, 1))
    ) trainInfos <- mkTRegFile(
        replicate(Invalid)
    );
    Integer trainInfosWritePort_preds = valueOf(numPreds) + 1;
    Integer trainInfosWritePort_deletions = 0;
    // Each prediction may replace another and we assume the old one to be correct. One more slot for an explicit update.
    Vector#(TAdd#(numPreds, 1), RWire#(UpdateInfo#(tokenT, resultT))) updateInfos <- replicateM(mkUnsafeRWire);


    function ActionValue#(tokenT) generatePredictionToken(Integer sup) = actionvalue
        let token = currentPredictionToken[sup];
        currentPredictionToken[sup] <= token + 1;
        return token;
    endactionvalue;

    function globalHistoryT addGlobalHistory(globalHistoryT gh, Maybe#(resultT) new_item);
        return shiftOutFromN(makeGlobalHistoryItem(new_item), gh, 1);
    endfunction
    
    // Get the global history with relevant predictions for previous instructions in this cycle's batch, excluding i.
    function ActionValue#(globalHistoryT) globalHistoryWithBatchHistoryUpTo(Integer i) = actionvalue
        dynamicAssert(i <= valueOf(numPreds), "i must be <= numPreds");
        globalHistoryT globalHistoryWithBatchHistory = globalHistory;
        for (Integer j = 0; j < i; j = j+1)
            if (batchHistory[j].wget() matches tagged Valid .result)
                globalHistoryWithBatchHistory = addGlobalHistory(globalHistoryWithBatchHistory, result);
        return globalHistoryWithBatchHistory;
    endactionvalue;

    rule updateGlobalHistory;
        // Reading all of `batchHistory` causes this rule to be scheduled after all predictions.
        let gh <- globalHistoryWithBatchHistoryUpTo(valueOf(numPreds)); globalHistory <= gh;
    endrule

    for (Integer i = 0; i < valueOf(numPreds) + 1; i = i + 1)
    (* fire_when_enabled *)
    rule doUpdate;
        if (updateInfos[i].wget() matches tagged Valid .updateInfo) begin
            let token = updateInfo.token;
            let m_m_actual = updateInfo.actual;
            // Sometimes this method may do nothing (no prediction was made with this token).
            let maybeTrainInfo = trainInfos.read[i].read(token);
            if (maybeTrainInfo matches tagged Valid .trainInfo) begin
                // mispred used to be given explicitly, this is a way to get it again.
                Bool mispred;
                Maybe#(resultT) m_actual;  // This used to be a resultT but became a maybe when I introduced tagged entries.
                if (m_m_actual matches tagged Valid .m_actual_) begin
                    mispred = (m_actual_ != trainInfo.prediction);
                    m_actual = m_actual_;
                end else begin
                    mispred = False;
                    // Deal with implicit updates (old predictions) by assuming we are correct.
                    m_actual = trainInfo.prediction;
                end

                let oldPTE = predictionTable.read[valueOf(numPreds)+i].read(trainInfo.index);
                let m_oldVwc = oldPTE.m_vwc;
                let newPTE = PredictionTableEntry {m_vwc: Invalid, tag: ?};
                if (m_actual matches tagged Valid .actual) begin
                    // Should have hit.
                    if (oldPTE.tag == trainInfo.tag &&& m_oldVwc matches tagged Valid .oldVwc) begin
                        let newVwc = updateValueWithConfidence(oldVwc, actual);
                        newPTE = PredictionTableEntry {
                            m_vwc: Valid(newVwc),
                            tag: oldPTE.tag
                        };
                    end else begin
                        // Allow a different tag if confidence is 0 or entry is invalid, otherwise decrement confidence.
                        if (m_oldVwc matches tagged Valid .oldVwc) begin
                            if (oldVwc.confidence == 0)
                                newPTE = PredictionTableEntry {
                                    m_vwc: Valid(ValueWithConfidence {value: actual, confidence: 0}),
                                    tag: trainInfo.tag
                                };
                            else
                                newPTE = PredictionTableEntry {
                                    m_vwc: Valid(ValueWithConfidence {value: oldVwc.value, confidence: oldVwc.confidence - 1}),
                                    tag: oldPTE.tag
                                };
                        end else
                            newPTE = PredictionTableEntry {
                                m_vwc: Valid(ValueWithConfidence {value: actual, confidence: 0}),
                                tag: trainInfo.tag
                            };
                    end
                    
                end else begin
                    // Was/would have been correct to miss.
                    if (oldPTE.tag == trainInfo.tag) begin
                        newPTE = PredictionTableEntry {
                            m_vwc: Invalid,
                            tag: trainInfo.tag
                        };
                    end
                end
                predictionTable.write[i].write(trainInfo.index, newPTE);

                // Signal deletion of this training info. If it is written to later this deletion does not take effect.
                trainInfos.write[trainInfosWritePort_deletions + i].write(token, Invalid);

                if (mispred) begin
                    // Rollback global history to before this prediction then add the correct result. 
                    globalHistory <= addGlobalHistory(trainInfo.globalHistory, m_actual);
                    // Remove all other training information since the predictions should not have been made.
                    trainInfos.clear;
                end
            end
        end
    endrule

    function Predict#(tokenT, resultT) superscalarPredict(Integer sup);
        return (interface Predict#(tokenT, resultT);
            method ActionValue#(PredictResult#(tokenT, resultT)) predict;
                // Get the true masked PC for this prediction.
                Addr pc = pcReg + (fromInteger(sup) << countZerosLSB(pcBitMask));
                choppedAddr pcChopped = extractMask(pcBitMask, pc);
                Bit#(numTagBits) tag = extractMask(pcTagBitMask, pc);

                // Account for previous instructions in superscalar batch.
                let thisGlobalHistory <- globalHistoryWithBatchHistoryUpTo(sup);
                index index = {pcChopped, pack(thisGlobalHistory)};

                let pte = predictionTable.read[sup].read(index);
                Maybe#(resultT) prediction = Invalid;
                if (pte.tag == tag &&& pte.m_vwc matches tagged Valid .vwc)
                    prediction = Valid(vwc.value);

                // Record that a prediction was made with the result.
                batchHistory[sup].wset(prediction);

                let predictionToken <- generatePredictionToken(sup);
                TrainInfo#(index, resultT, globalHistoryT, numTagBits) trainInfo = TrainInfo {
                    index: index,
                    prediction: prediction,
                    globalHistory: thisGlobalHistory,
                    tag: tag
                };
                trainInfos.write[trainInfosWritePort_preds + sup].write(predictionToken, Valid(trainInfo));
                // Assume we were correct for a possible prediction this entry replaces.
                updateInfos[sup].wset(UpdateInfo {token: predictionToken, actual: Invalid});

                return PredictResult {
                    token: predictionToken,
                    prediction: prediction
                };
            endmethod
        endinterface);
    endfunction
    interface predict = genWith(superscalarPredict);

    method Action update(tokenT token, Maybe#(resultT) actual);
        updateInfos[valueOf(numPreds)].wset(
            UpdateInfo {token: token, actual: Valid(actual)}
        );
    endmethod

    method Action nextPc(Addr pc);
        pcReg <= pc;
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
