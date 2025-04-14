import ProcTypes::*;  // for SupSize, SupSizeX2
import Types::*;  // for Addr
import TRegFile::*;
import Vector::*;


// dirpred predictionTable

export mkOptimisedGSelectPredictionTable;
export Opt_GSelect_Index;
export Opt_GSelect_ValueWithHysteresis(..);

typedef Bit#(12) Opt_GSelect_Index;
typedef struct {
    Bool value;
    UInt#(1) hysteresis;
} Opt_GSelect_ValueWithHysteresis deriving(Bits, Eq, FShow);

module [Module] mkOptimisedGSelectPredictionTable(TRegFile#(
    Opt_GSelect_Index,
    Opt_GSelect_ValueWithHysteresis,
    TAdd#(SupSize, 1)
));
    let m <- mkTRegFile(replicate(
        Opt_GSelect_ValueWithHysteresis {value: False, hysteresis: 0}
    ));
    return m;
endmodule


// dirpred trainInfos

export mkOptimisedGSelectTrainInfos;
export Opt_GSelect_GSelectDirPredToken;
export Opt_GSelect_GSelectTrainInfo;

typedef UInt#(8) Opt_GSelect_GSelectDirPredToken;
typedef struct {
    Bit#(12) index;
    Opt_GSelect_ValueWithHysteresis vwh;
    Vector#(8, Bool) globalHistory;
} Opt_GSelect_GSelectTrainInfo deriving(Bits, Eq, FShow);

module [Module] mkOptimisedGSelectTrainInfos(TRegFile#(
    Opt_GSelect_GSelectDirPredToken,
    Maybe#(Opt_GSelect_GSelectTrainInfo),
    TAdd#(TMul#(SupSize, 2), 1)
));
    Vector#(
        TExp#(SizeOf#(Opt_GSelect_GSelectDirPredToken)),
        Maybe#(Opt_GSelect_GSelectTrainInfo)
    ) init = replicate(Invalid);
    let m <- mkTRegFile(init);
    return m;
endmodule




// btb predictionTable

export mkOptimisedGSelectBtbPredictionTable;
export Opt_GSelectBtb_Index;
export Opt_GSelectBtb_ValueWithHysteresis(..);

typedef Bit#(12) Opt_GSelectBtb_Index;
typedef struct {
    Maybe#(Addr) value;
    UInt#(1) hysteresis;
} Opt_GSelectBtb_ValueWithHysteresis deriving(Bits, Eq, FShow);

module [Module] mkOptimisedGSelectBtbPredictionTable(TRegFile#(
    Opt_GSelectBtb_Index,
    Opt_GSelectBtb_ValueWithHysteresis,
    TAdd#(SupSizeX2, 1)
));
    let m <- mkTRegFile(replicate(
        Opt_GSelectBtb_ValueWithHysteresis {value: Invalid, hysteresis: 0}
    ));
    return m;
endmodule


// dirpred trainInfos

export mkOptimisedGSelectBtbTrainInfos;
export Opt_GSelectBtb_GSelectBtbToken;
export Opt_GSelectBtb_GSelectTrainInfo;

typedef UInt#(8) Opt_GSelectBtb_GSelectBtbToken;
typedef struct {
    Bit#(12) index;
    Opt_GSelectBtb_ValueWithHysteresis vwh;
    Vector#(8, Bool) globalHistory;
} Opt_GSelectBtb_GSelectTrainInfo deriving(Bits, Eq, FShow);

module [Module] mkOptimisedGSelectBtbTrainInfos(TRegFile#(
    Opt_GSelectBtb_GSelectBtbToken,
    Maybe#(Opt_GSelectBtb_GSelectTrainInfo),
    TAdd#(TMul#(SupSizeX2, 2), 1)
));
    Vector#(
        TExp#(SizeOf#(Opt_GSelectBtb_GSelectBtbToken)),
        Maybe#(Opt_GSelectBtb_GSelectTrainInfo)
    ) init = replicate(Invalid);
    let m <- mkTRegFile(init);
    return m;
endmodule