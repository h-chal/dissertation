import ISA_Decls::*;
import Types::*;

import Ehr::*;
import Vector::*;
import RegFile::*;
import Assert::*;
import TRegFile::*;
import ValueWithConfidence::*;

export ParamGSelect(..);
export Predict(..);
export PredictResult(..);
export mkParamGSelect;


typedef struct {
    tokenT token;
    resultT prediction;
} PredictResult#(type tokenT, type resultT) deriving(Bits, Eq, FShow);

interface Predict#(type tokenT, type resultT);
    method ActionValue#(PredictResult#(tokenT, resultT)) predict;
endinterface

interface ParamGSelect#(
    type resultT,
    type tokenT,
    numeric type numPreds,
    numeric type numPcBits,
    numeric type numGlobalHistoryItems,
    type globalHistoryT,
    numeric type numConfidenceBits
);
    method Action nextPc(Addr nextPc);
    interface Vector#(numPreds, Predict#(tokenT, resultT)) predict;
    method Action update(tokenT token, resultT actual);
    method Action flush;
    method Bool flush_done;
endinterface


typedef struct {
    indexT index;
    resultT prediction;
    globalHistoryT globalHistory;  // Some redundancy with index.
} TrainInfo#(type indexT, type resultT, type globalHistoryT) deriving(Bits, Eq, FShow);

typedef struct {
    tokenT token;
    Maybe#(resultT) actual;  // Valid if explicit update, Invalid if implicit update.
} UpdateInfo#(type tokenT, type resultT) deriving(Bits);

module mkParamGSelect#(
    Addr pcBitMask,  // Must have numPcBits set bits.
    resultT defaultPrediction,
    function globalHistoryItemT makeGlobalHistoryItem(resultT result)  // Which bits of the result to remember for global history.
) (ParamGSelect#(resultT, tokenT, numPreds, numPcBits, numGlobalHistoryItems, globalHistoryItemT, numConfidenceBits))
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

    Reg#(choppedAddr) pcChoppedBase <- mkRegU;
    // The global history of previous results, including predictions.
    Reg#(globalHistoryT) globalHistory <- mkRegU;
    TRegFile#(
        index,
        ValueWithConfidence#(resultT, numConfidenceBits),
        TAdd#(numPreds, TAdd#(numPreds, 1)),
        TAdd#(numPreds, 1)
    ) predictionTable <- mkTRegFile(
        replicate(ValueWithConfidence {value: defaultPrediction, confidence: 0})
    );
    // Registers to store the global history for this superscalar batch.
    Vector#(numPreds, RWire#(resultT)) batchHistory <- replicateM(mkUnsafeRWire);
    Ehr#(numPreds, tokenT) currentPredictionToken <- mkEhr(0);
    TRegFile#(
        tokenT,
        Maybe#(TrainInfo#(index, resultT, globalHistoryT)),
        TAdd#(numPreds, 1),
        TAdd#(numPreds, TAdd#(numPreds, 1))
    ) trainInfos <- mkTRegFile(
        replicate(Invalid)
    );
    // Each prediction may replace another and we assume the old one to be correct. One more slot for an explicit update.
    Vector#(TAdd#(numPreds, 1), RWire#(UpdateInfo#(tokenT, resultT))) updateInfos <- replicateM(mkUnsafeRWire);


    function ActionValue#(tokenT) generatePredictionToken(Integer sup) = actionvalue
        let token = currentPredictionToken[sup];
        currentPredictionToken[sup] <= token + 1;
        return token;
    endactionvalue;

    function globalHistoryT addGlobalHistory(globalHistoryT gh, resultT new_item);
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
            let maybeActual = updateInfo.actual;
            // Sometimes this method may do nothing (no prediction was made with this token).
            let maybeTrainInfo = trainInfos.read[i].read(token);
            if (maybeTrainInfo matches tagged Valid .trainInfo) begin
                // mispred used to be given explicitly, this is a way to get it again.
                Bool mispred;
                resultT actual;
                if (maybeActual matches tagged Valid .actual_) begin
                    mispred = (actual_ != trainInfo.prediction);
                    actual = actual_;
                end else begin
                    mispred = False;
                    // Deal with implicit updates (old predictions) by assuming we are correct.
                    actual = trainInfo.prediction;
                end

                // Update value with confidence and signal to store it.
                let newVwc = updateValueWithConfidence(
                    predictionTable.read[valueOf(numPreds)+i].read(trainInfo.index),
                    actual
                );
                predictionTable.write[i].write(trainInfo.index, newVwc);

                // Signal deletion of this training info.
                trainInfos.write[valueOf(numPreds)+i].write(token, Invalid);

                if (mispred) begin
                    // Rollback global history to before this prediction then add the correct result. 
                    globalHistory <= addGlobalHistory(trainInfo.globalHistory, actual);
                    // Remove all other training information since the predictions should not have been made.
                    trainInfos.clear;
                end
            end
        end
    endrule

    // Vector to interfaces since Toooba is superscalar.
    // interface Vector#(numPreds, DirPred#(trainInfoT)) pred;
    function Predict#(tokenT, resultT) superscalarPredict(Integer sup);
        return (interface Predict#(tokenT, resultT);
            method ActionValue#(PredictResult#(tokenT, resultT)) predict;
                // Get the true PC for this prediction.
                let pcChopped = pcChoppedBase + fromInteger(sup);

                // Account for previous instructions in superscalar batch.
                let thisGlobalHistory <- globalHistoryWithBatchHistoryUpTo(sup);
                index index = {pcChopped, pack(thisGlobalHistory)};

                let vwc = predictionTable.read[sup].read(index);
                let prediction = vwc.value;

                // Record that a prediction was made with the result.
                batchHistory[sup].wset(prediction);

                let predictionToken <- generatePredictionToken(sup);
                TrainInfo#(index, resultT, globalHistoryT) trainInfo = TrainInfo {
                    index: index,
                    prediction: prediction,
                    globalHistory: thisGlobalHistory
                };
                trainInfos.write[sup].write(predictionToken, Valid(trainInfo));
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

    method Action update(tokenT token, resultT actual);
        updateInfos[valueOf(numPreds)].wset(
            UpdateInfo {token: token, actual: Valid(actual)}
        );
    endmethod

    method Action nextPc(Addr pc);
        // Put masked bits of pc into a register that only holds the masked bits.
        choppedAddr maskedPc = 0;
        Integer outIndex = 0;
        for (Integer i = 0; i < valueOf(XLEN); i = i + 1)
            if (pcBitMask[i] == 1) begin
                maskedPc[outIndex] = pc[i];
                outIndex = outIndex + 1;
            end
        pcChoppedBase <= maskedPc;
    endmethod

    method flush = noAction;
    method flush_done = True;
endmodule
