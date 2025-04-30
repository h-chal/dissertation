import StmtFSM::*;
import Assert::*;
import ValueWithConfidence::*;
import Vector::*;

typedef enum {PorterRobinson, Underscores, FrostChildren, SaoirseDream} Musician deriving (Bits, Eq);

(* synthesize *)
module mkTest_ValueWithConfidence_Enum_2bits (Empty);
    // A Musician (enum) with 2 bits of confidence: very weak (0), weak (1), strong (2), very strong (3).

    // My (initial) favourite musician is underscores and I am strongly confident about this.
    Reg#(ValueWithConfidence#(Musician, 2)) favMusician <- mkReg(ValueWithConfidence {
        value: Underscores,
        confidence: 2
    });

    mkAutoFSM(seq
        // Listen to underscores:
        action
            favMusician <= updateValueWithConfidence(favMusician, Underscores);
            // "Arms, body, legs, flesh, skin, bones, sinew, good luck!"
        endaction
        action
            // Now I like underscores very strongly.
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 3, "fail");
        endaction

        action
            favMusician <= updateValueWithConfidence(favMusician, Underscores);
            // "All I wanted was a 'yes' or a 'maybe'..."
        endaction
        action
            // It's impossible to like underscores more than I already did.
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 3, "fail");
        endaction

        // Listen to other artists:
        action
            favMusician <= updateValueWithConfidence(favMusician, FrostChildren);
            // "Wouldn't life be better at a snail's pace?"
        endaction
        action
            // underscores is still my favourite but not as strong now.
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 2, "fail");
        endaction
        action
            favMusician <= updateValueWithConfidence(favMusician, FrostChildren);
            // "I don't know which thing about me is worse"
        endaction
        action
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 1, "fail");
        endaction

        // Back to underscores:
        action
            favMusician <= updateValueWithConfidence(favMusician, Underscores);
            // "I saw the reaper and I didn't even try this time"
        endaction
        action
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 2, "fail");
        endaction

        action
            favMusician <= updateValueWithConfidence(favMusician, SaoirseDream);
            // "I am the target I've been trying to reach"
        endaction
        action
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 1, "fail");
        endaction
        action
            favMusician <= updateValueWithConfidence(favMusician, PorterRobinson);
            // "I need a next life 'cause I'm not satisfied to know you just once"
        endaction
        action
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 0, "fail");
        endaction

        action
            favMusician <= updateValueWithConfidence(favMusician, Underscores);
            // "He's just like me, she's just like me, they're just like me"
        endaction
        action
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 1, "fail");
        endaction

        action
            favMusician <= updateValueWithConfidence(favMusician, SaoirseDream);
            // "Shave off the corners, tuck broad shoulders"
        endaction
        action
            dynamicAssert(favMusician.value == Underscores, "fail");
            dynamicAssert(favMusician.confidence == 0, "fail");
        endaction

        // A song from anyone but underscores gives me a new favourite.
        action
            favMusician <= updateValueWithConfidence(favMusician, PorterRobinson);
            // "I'll be alive next year"
        endaction
        action
            dynamicAssert(favMusician.value == PorterRobinson, "fail");
            dynamicAssert(favMusician.confidence == 0, "fail");
        endaction

        // A song from anyone but Porter Robinson gives me a new favourite.
        action
            favMusician <= updateValueWithConfidence(favMusician, SaoirseDream);
            // "Bridges all go down in flames"
        endaction
        action
            dynamicAssert(favMusician.value == SaoirseDream, "fail");
            dynamicAssert(favMusician.confidence == 0, "fail");
        endaction

        // A song from anyone but Saoirse Dream gives me a new favourite.
        action
            favMusician <= updateValueWithConfidence(favMusician, PorterRobinson);
            // (The chiptune in Knock Yourself Out XD)
        endaction
        action
            dynamicAssert(favMusician.value == PorterRobinson, "fail");
            dynamicAssert(favMusician.confidence == 0, "fail");
        endaction
        action
            favMusician <= updateValueWithConfidence(favMusician, PorterRobinson);
            // "The world is lucky to be your home"
        endaction
        action
            dynamicAssert(favMusician.value == PorterRobinson, "fail");
            dynamicAssert(favMusician.confidence == 1, "fail");
        endaction
    endseq);
endmodule
