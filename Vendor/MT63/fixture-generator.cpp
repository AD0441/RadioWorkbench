// Test-only MT63 transmitter. Never included in RadioWorkbench.app.
// Uses upstream fldigi MT63tx rather than the receive adapter to make PCM.
// SPDX-License-Identifier: GPL-3.0-or-later
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "dsp.h"
#include "mt63base.h"
int main(int argc, char **argv) {
    if (argc != 5) return 2;
    const int bandwidth = std::atoi(argv[1]);
    const bool longInterleave = !std::strcmp(argv[2], "long");
    const double center = std::atof(argv[3]);
    MT63tx transmitter;
    if (transmitter.Preset(center, bandwidth, longInterleave)) return 3;
    auto output = [&] {
        for (int i = 0; i < transmitter.Comb.Output.Len; ++i) {
            float sample = static_cast<float>(transmitter.Comb.Output.Data[i] * 0.5);
            if (std::fwrite(&sample, sizeof(sample), 1, stdout) != 1) std::exit(4);
        }
    };
    // Give the RX synchronizer time to acquire before the first user character.
    for (int i = 0; i < 100; ++i) { transmitter.SendChar(0); output(); }
    for (const char *ch = argv[4]; *ch; ++ch) { transmitter.SendChar(*ch); output(); }
    for (int i = 0; i < transmitter.DataInterleave + 100; ++i) { transmitter.SendChar(0); output(); }
    for (int i = 0; i < 16; ++i) { transmitter.SendJam(); output(); }
    for (int i = 0; i < 32; ++i) { transmitter.SendSilence(); output(); }
    return std::ferror(stdout) ? 4 : 0;
}
