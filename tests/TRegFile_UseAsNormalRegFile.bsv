import StmtFSM::*;
import Assert::*;
import TRegFile::*;
import Vector::*;

(* synthesize *)
module mkTest_TRegFile_UseAsNormalRegFile (Empty);
    // Try using it as a normal RegFile.
    Vector#(4, Bool) init = newVector;
    init[0]=False; init[1]=True; init[2]=True; init[3]=False;
    TRegFile#(Bit#(2), Bool, 1, 1) rf <- mkTRegFile(init);

    Integer theOnlyReadPort = 0;
    Integer theOnlyWritePort = 0;

    mkAutoFSM(seq
        // Read all the slots.
        action
            let rf0 = rf.read[theOnlyReadPort].read(0);
            dynamicAssert(rf0 == False, "fail");
        endaction
        action
            let rf1 = rf.read[theOnlyReadPort].read(1);
            dynamicAssert(rf1 == True, "fail");
        endaction
        action
            let rf2 = rf.read[theOnlyReadPort].read(2);
            dynamicAssert(rf2 == True, "fail");
        endaction
        action
            let rf3 = rf.read[theOnlyReadPort].read(3);
            dynamicAssert(rf3 == False, "fail");
        endaction

        // Write slot 2 and read it back.
        action
            rf.write[theOnlyWritePort].write(2, False);
        endaction
        action
            let rf2 = rf.read[theOnlyReadPort].read(2);
            dynamicAssert(rf2 == False, "fail");
        endaction

        // Read and write slot 0 in the same action.
        action
            rf.write[theOnlyWritePort].write(0, True);
            let rf0 = rf.read[theOnlyReadPort].read(0);
            dynamicAssert(rf0 == False, "fail"); // We shouldn't see the write until the next action.
        endaction
        action
            let rf0 = rf.read[theOnlyReadPort].read(0);
            dynamicAssert(rf0 == True, "fail"); // Now we should see the write.
        endaction

        // Read and write different slots in the same action.
        action
            rf.write[theOnlyWritePort].write(0, False);
            let rf3 = rf.read[theOnlyReadPort].read(3);
            dynamicAssert(rf3 == False, "fail");
        endaction
        action
            let rf0 = rf.read[theOnlyReadPort].read(0);
            dynamicAssert(rf0 == False, "fail");
        endaction
    endseq);
endmodule
