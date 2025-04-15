// TODO try write queue
// TODO prioritise latest write not earliest

import Vector::*;
export TRegFile(..);
export mkTRegFile;
export TReader(..);
export TWriter(..);


// Transactional Register File
interface TRegFile#(type index, type t, numeric type numReadPorts, numeric type numWritePorts);
    interface Vector#(numReadPorts, TReader#(index, t)) read;
    interface Vector#(numWritePorts, TWriter#(index, t)) write;
    method Action clear();
endinterface

interface TReader#(type index, type t);
    method t read(index i);
endinterface

interface TWriter#(type index, type t);
    method Action write(index i, t v);
endinterface


module mkTRegFile#(Vector#(TExp#(indexSz), t) init)
	(TRegFile#(index, t, numReadPorts, numWritePorts))
	provisos (
        Bits#(index, indexSz), PrimIndex#(index, indexSz), Arith#(index), Ord#(index),
        Bits#(t, tSz)
    );

    module mkRegInit#(Integer i) (Reg#(t));
        let m <- mkReg(init[i]);
        return m;
    endmodule
	Vector#(TExp#(SizeOf#(index)), Reg#(t)) regs <- genWithM(mkRegInit);
    Vector#(numWritePorts, RWire#(Tuple2#(index, t))) writeWires <- replicateM(mkRWire);
    PulseWire clearWire <- mkPulseWireOR;

    for (Integer i = 0; i < valueOf(TExp#(indexSz)); i = i + 1)
        rule doWrite(!clearWire);
            t newVal = regs[i];
            for (Integer w = 0; w < valueOf(numWritePorts); w = w + 1)
                if (writeWires[w].wget() matches tagged Valid {.writeIndex, .v} &&& writeIndex == fromInteger(i))
                    newVal = v;
            regs[i] <= newVal;
        endrule

    rule doClear(clearWire);
        writeVReg(regs, init);
    endrule


    function TWriter#(index, t) mkTWriter(Integer w);
        return interface TWriter#(index, t);
            method Action write(index i, t v);
                writeWires[w].wset(tuple2(i, v));
            endmethod
        endinterface;
    endfunction
    interface read = replicate(
        interface TReader#(index, t);
            method t read(index i);
                return regs[i];
            endmethod
        endinterface
    );
    interface write = genWith(mkTWriter);
    interface clear = clearWire.send();
endmodule