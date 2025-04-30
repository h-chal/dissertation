typedef struct {
    t value;
    UInt#(numConfidenceBits) confidence;
} ValueWithConfidence#(type t, numeric type numConfidenceBits) deriving (Bits, Eq, FShow);


function ValueWithConfidence#(t, numConfidenceBits) updateValueWithConfidence
    (ValueWithConfidence#(t, numConfidenceBits) current, t newValue)
    provisos (Eq#(t));

    if (current.value == newValue)
        return ValueWithConfidence {
            value: current.value,
            confidence: boundedPlus(current.confidence, 1)
        };
    else begin
        if (current.confidence > 0)
            return ValueWithConfidence {
                value: current.value,
                confidence: current.confidence - 1
            };
        else
            return ValueWithConfidence {
                value: newValue,
                confidence: 0
            };
    end
endfunction