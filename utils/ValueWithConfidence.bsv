typedef struct {
    t value;
    UInt#(1) confidence;
} ValueWithConfidence#(type t) deriving (Bits, Eq, FShow);


function ValueWithConfidence#(t) updateValueWithConfidence(ValueWithConfidence#(t) current, t newValue) provisos (Eq#(t));
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