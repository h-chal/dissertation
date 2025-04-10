// TODO try numReadPorts
// TODO try write queue

import Vector::*;
export TRegFile(..);
export mkTRegFile;

// Transactional Register File
interface TRegFile#(type index, type t, numeric type numWritePorts);
	interface Vector#(TExp#(SizeOf#(index)), ReadOnly#(t)) read;
	interface Vector#(numWritePorts, WriteOnly#(Tuple2#(index, t))) write;
    method Action clear();
endinterface

module [Module] mkTRegFile#(Vector#(TExp#(indexSz), t) init)
	(TRegFile#(index, t, numWritePorts))
	provisos (
        Bits#(index, indexSz), PrimIndex#(index, indexSz), Arith#(index), Ord#(index),
        Bits#(t, tSz)
    );

    function Module#(Reg#(t)) mkRegInit(Integer i);
        return mkReg(init[i]);
    endfunction
	Vector#(TExp#(SizeOf#(index)), Reg#(t)) regs <- genWithM(mkRegInit);
    Vector#(numWritePorts, RWire#(Tuple2#(index, t))) writeWires <- replicateM(mkRWire);

    PulseWire clearWire <- mkPulseWireOR;

    for (Integer i = 0; i < valueOf(TExp#(indexSz)); i = i + 1)
        rule doWrite(!clearWire);
            Bool done = False;
            for (Integer w = 0; w < valueOf(numWritePorts) && !done; w = w + 1)
                if (writeWires[w].wget() matches tagged Valid {.writeIndex, .v})
                    // I don't think I can pattern match an index.
                    if (writeIndex == fromInteger(i)) begin
                        done = True;
                        regs[i] <= v;
                    end
        endrule


    rule doClear(clearWire);
        writeVReg(regs, init);
    endrule

    function ReadOnly#(t) mkRead(Integer i);
        return interface ReadOnly;
            method t _read;
                return regs[i];
            endmethod
        endinterface;
    endfunction

    function WriteOnly#(Tuple2#(index, t)) mkWrite(Integer w);
        return interface WriteOnly;
            method Action _write(Tuple2#(index, t) x);
                writeWires[w].wset(x);
            endmethod
        endinterface;
    endfunction

    interface read = genWith(mkRead);
    interface write = genWith(mkWrite);
    interface clear = clearWire.send();
endmodule