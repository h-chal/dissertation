import StmtFSM::*;
import Assert::*;
import TRegFile::*;
import Vector::*;

(* synthesize *)
module mkTest_TRegFile_MultiReadMultiWrite (Empty);
    Vector#(2, UInt#(8)) init = newVector;
    init[0]=127; init[1]=87;
    TRegFile#(Bit#(1), UInt#(8), 2, 2) rf <- mkTRegFile(init);

    Integer readPort0 = 0;
    Integer readPort1 = 1;
    Integer writePort0 = 0;
    Integer writePort1 = 1;

    mkAutoFSM(seq
        // Read the same slot from both ports.
        action
            let v1 = rf.read[readPort0].read(0);
            let v2 = rf.read[readPort1].read(0);
            dynamicAssert(v1 == v2, "fail");
            dynamicAssert(v1 == 127, "fail");
        endaction

        // Read both slots.
        action
            let v1 = rf.read[readPort1].read(0);
            let v2 = rf.read[readPort0].read(1);
            dynamicAssert(v1 == 127, "fail");
            dynamicAssert(v2 == 87, "fail");
        endaction

        // Write both slots then read them both back.
        action
            rf.write[writePort0].write(0, 10);
            rf.write[writePort1].write(1, 54);
        endaction
        action
            let v1 = rf.read[readPort1].read(0);
            let v2 = rf.read[readPort0].read(1);
            dynamicAssert(v1 == 10, "fail");
            dynamicAssert(v2 == 54, "fail");
        endaction

        // Write to the same slot on both ports. Only the later port's write should be seen.
        action
            rf.write[writePort1].write(0, 50); // Later port.
            rf.write[writePort0].write(0, 22); // Earlier port.
        endaction
        action
            let v1 = rf.read[readPort0].read(0);
            dynamicAssert(v1 == 50, "fail");
        endaction
    endseq);
endmodule
