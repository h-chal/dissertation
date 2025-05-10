#!python

from pathlib import Path
import re

# exes = ["original", "myBdp_originalNap", "originalBdp_myNap", "myBdp_myNap"]
exes = ["myBdp_originalNap"]
# bms = ["adpcm_decode", "adpcm_encode", "aes", "bitcount", "blowfish", "dijkstra", "patricia", "picojpeg", "qsort", "rc4", "sha"]
bms = ["adpcm_decode", "adpcm_encode", "picojpeg"]

for exe in exes:
    print("\n\n\n\n")
    print("="*20)
    print("="*20)
    print("Config:", exe)

    for bm in bms:
        print("\n\n")
        print("="*20)
        print("Benchmark:", bm)

        file = Path("logs") / exe / (bm + ".bin.log")
        bdp_trains = bdp_mispreds = nap_dec_trains = 0

        with open(file, "r") as f:
            for line in f:
                if "instret" in line:
                    last_instret_line = line
                if "ACCURACY_MONITORING TrainBDP" in line:
                    bdp_trains += 1
                    if " 1" in line:
                        bdp_mispreds += 1
                elif "ACCURACY_MONITORING TrainNAP" in line:
                    nap_dec_trains += 1

            groups = re.findall(r'\d+', last_instret_line)
            instructions = 1 + int(groups[0])
            cycles = groups[-1]


        with open(file, "r") as f:
            halfway = (instructions - 1 ) // 2
            halfway_pos = None
            for i, line in enumerate(f):
                if "instret:" + str(halfway) in line:
                    halfway_pos = i
                    break

        with open(file, "r") as f:
            num_invalids_halfway = None
            if halfway_pos:
                for _ in range(halfway_pos):
                    next(f)
                for line in f:
                    if "TREGFILE_ANALYSIS 24595658764946068820" in line:
                        num_invalids_halfway = int(re.findall(r'\d+', line)[-1])
                        break


        print("Instructions:", instructions)
        print("Cycles:", cycles)

        print("BDP trains:", bdp_trains)
        print("BDP mispreds:", bdp_mispreds)
        print("NAP decode trains:", nap_dec_trains)

        if num_invalids_halfway:
            print("Invalid entries halfway through:", num_invalids_halfway)
