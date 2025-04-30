import StmtFSM::*;
import Assert::*;
import ValueWithConfidence::*;
import Vector::*;

(* synthesize *)
module mkTest_ValueWithConfidence_Bool_1bit (Empty);
    // BDP case: Boolean with 1 bit confidence equivalent to 2 bit saturating counter.

    // Put them both in a register.
    Reg#(UInt#(2)) satCounter <- mkReg('b01); // Weakly False.
    Reg#(ValueWithConfidence#(Bool, 1)) vwc <- mkReg(ValueWithConfidence {value: False, confidence: 0});

    function Bool getSatVal = pack(satCounter)[1] == 1;
    // Confident if both bits are the same.
    function UInt#(1) getSatConf = pack(satCounter)[1] == pack(satCounter)[0] ? 1 : 0;

    function Action assertEquiv(String s) = action
        dynamicAssert(vwc.value == getSatVal, s);
        dynamicAssert(vwc.confidence == getSatConf, s);
    endaction;

    function Action incVwc = action vwc <= updateValueWithConfidence(vwc, True); endaction;
    function Action decVwc = action vwc <= updateValueWithConfidence(vwc, False); endaction;
    function Action incSat = action satCounter <= boundedPlus(satCounter, 1); endaction;
    function Action decSat = action satCounter <= boundedMinus(satCounter, 1); endaction;
    function Action inc = action incVwc; incSat; endaction;
    function Action dec = action decVwc; decSat; endaction;
    
    mkAutoFSM(seq
        action
            assertEquiv("1");
        endaction

        action
            inc;
        endaction
        action
            assertEquiv("2");
        endaction
        action
            inc;
        endaction
        action
            assertEquiv("3");
        endaction
        action
            inc;
        endaction
        action
            assertEquiv("4");
        endaction
        action
            inc;
        endaction
        action
            assertEquiv("5");
        endaction

        action
            dec;
        endaction
        action
            assertEquiv("6");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("7");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("8");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("9");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("10");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("11");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("12");
        endaction

        action
            inc;
        endaction
        action
            assertEquiv("13");
        endaction
        action
            inc;
        endaction
        action
            assertEquiv("14");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("15");
        endaction
        action
            inc;
        endaction
        action
            assertEquiv("16");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("17");
        endaction
        action
            dec;
        endaction
        action
            assertEquiv("18");
        endaction
        action
            inc;
        endaction
        action
            assertEquiv("19");
        endaction
    endseq);
endmodule
