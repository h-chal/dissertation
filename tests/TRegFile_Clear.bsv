import StmtFSM::*;
import Assert::*;
import TRegFile::*;
import Vector::*;

(* synthesize *)
module mkTest_TRegFile_Clear (Empty);
    Vector#(2, Maybe#(Bit#(2))) init = newVector;
    init[0]=Valid(2); init[1]=Invalid;
    TRegFile#(Bit#(1), Maybe#(Bit#(2)), 2, 1) rf <- mkTRegFile(init);

    Integer readPort0 = 0;
    Integer readPort1 = 1;
    Integer theOnlyWritePort = 0;

    mkAutoFSM(seq
        action
            rf.write[theOnlyWritePort].write(0, Valid(0));
        endaction
        action
            rf.clear;
        endaction
        action
            let rf0 = rf.read[readPort0].read(0);
            let rf1 = rf.read[readPort1].read(1);
            dynamicAssert(rf0 == init[0], "fail");
            dynamicAssert(rf1 == init[1], "fail");
        endaction

        // A write in the same action as clear should be ignored.
        action
            rf.write[theOnlyWritePort].write(1, Valid(1));
            rf.clear;
        endaction
        action
            let rf0 = rf.read[readPort0].read(0);
            let rf1 = rf.read[readPort1].read(1);
            dynamicAssert(rf0 == init[0], "fail");
            dynamicAssert(rf1 == init[1], "fail");
        endaction
    endseq);
endmodule
