// TODO try write queue with filter for unnecessary writes
// TODO prioritise latest write not earliest

import Vector::*;
export TRegFile(..);
export mkTRegFile;
export TReader(..);
export TWriter(..);


// Transactional Register File
interface TRegFile#(type indexT, type dataT, numeric type numReadPorts, numeric type numWritePorts);
    interface Vector#(numReadPorts, TReader#(indexT, dataT)) read;
    interface Vector#(numWritePorts, TWriter#(indexT, dataT)) write;
    method Action clear();
endinterface

interface TReader#(type indexT, type dataT);
    method dataT read(indexT i);
endinterface

interface TWriter#(type indexT, type dataT);
    method Action write(indexT i, dataT v);
endinterface


module mkTRegFile#(Vector#(TExp#(indexSz), dataT) init)
	(TRegFile#(indexT, dataT, numReadPorts, numWritePorts))
	provisos (
        Bits#(indexT, indexSz), PrimIndex#(indexT, indexPrimIndex), Arith#(indexT), Ord#(indexT),
        Bits#(dataT, dataSz)
    );

    module mkRegInit#(Integer i) (Reg#(dataT));
        let m <- mkReg(init[i]);
        return m;
    endmodule
	Vector#(TExp#(indexSz), Reg#(dataT)) regs <- genWithM(mkRegInit);
    Vector#(numWritePorts, RWire#(Tuple2#(indexT, dataT))) writeWires <- replicateM(mkRWire);
    PulseWire clearWire <- mkPulseWireOR;

    for (Integer i = 0; i < valueOf(TExp#(indexSz)); i = i + 1)
        rule doWrite(!clearWire);
            dataT newVal = regs[i];
            for (Integer w = 0; w < valueOf(numWritePorts); w = w + 1)
                if (writeWires[w].wget() matches tagged Valid {.writeIndex, .v} &&& writeIndex == fromInteger(i))
                    newVal = v;
            regs[i] <= newVal;
        endrule

    rule doClear(clearWire);
        writeVReg(regs, init);
    endrule


    function TWriter#(indexT, dataT) mkTWriter(Integer w);
        return interface TWriter#(indexT, dataT);
            method Action write(indexT i, dataT v);
                writeWires[w].wset(tuple2(i, v));
            endmethod
        endinterface;
    endfunction
    interface read = replicate(
        interface TReader#(indexT, dataT);
            method dataT read(indexT i);
                return regs[i];
            endmethod
        endinterface
    );
    interface write = genWith(mkTWriter);
    interface clear = clearWire.send();
endmodule