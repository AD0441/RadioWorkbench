// RadioWorkbench standalone receive adapter for fldigi MT63 (GPL-3.0-or-later).
// Raw little-endian float32 mono, exactly 8000 Hz, stdin -> incremental JSONL.
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <unistd.h>
#include "dsp.h"
#include "mt63base.h"

static constexpr const char *revision = "61b97f4133c488063f3de1795c894d22d5032e8a";

static void quoted(const std::string &value) {
    std::putchar('"');
    for (unsigned char ch : value) {
        if (ch == '"' || ch == '\\') std::putchar('\\');
        if (ch >= 32 && ch < 127) std::putchar(ch);
        else std::printf("\\u%04x", ch);
    }
    std::putchar('"');
}

static bool number(const char *value, double &result) {
    char *end = nullptr;
    result = std::strtod(value, &end);
    return end != value && *end == '\0' && std::isfinite(result);
}

class Receiver {
    MT63rx decoder;
    double_buff input;
    double center;
    unsigned long long processed = 0;
    unsigned long long lockSamples = 0, warmupSamples = 0;
    bool previousLock = false, escape = false;
    unsigned long long lastStatus = 0;
public:
    Receiver(double frequency, int bandwidth, bool longInterleave) : center(frequency) {
        // Interleaver depth + synchronizer/decoder integration delay, measured
        // from lock acquisition. A fresh best-match buffer is not user text.
        warmupSamples = static_cast<unsigned long long>((longInterleave ? 64 : 32) + 32) *
            static_cast<unsigned long long>(800000 / bandwidth);
        if (input.EnsureSpace(256) || decoder.Preset(center, bandwidth, longInterleave, 16))
            throw std::bad_alloc();
    }

    void process(const float *samples, size_t count) {
        input.Len = static_cast<int>(count);
        for (size_t i = 0; i < count; ++i) {
            const double sample = samples[i];
            input.Data[i] = std::isfinite(sample) ? std::clamp(sample, -1.0, 1.0) : 0.0;
        }
        if (decoder.Process(&input)) throw std::bad_alloc();
        processed += count;
        const bool locked = decoder.SYNC_LockStatus() != 0;
        lockSamples = locked ? lockSamples + count : 0;
        const double confidence = std::clamp(decoder.SYNC_Confidence(), 0.0, 1.0);
        std::string text;
        // The receiver emits a best Walsh match even before the interleaver is
        // full. A minimum upstream FEC signal/noise metric avoids publishing
        // those random startup matches. It is a linear detector metric, not an
        // RF or calibrated audio SNR, and is deliberately not exported as dB.
        if (locked && lockSamples >= warmupSamples && decoder.FEC_SNR() >= 5.0) {
            for (int i = 0; i < decoder.Output.Len; ++i) {
                unsigned int ch = static_cast<unsigned char>(decoder.Output.Data[i]);
                if (ch == 127) { escape = true; continue; }
                if (escape) { ch += 128; escape = false; }
                if (ch >= 32 || ch == 10 || ch == 13 || ch == 9)
                    text.push_back(static_cast<char>(ch));
            }
        } else escape = false;
        // Status is at most once a second, plus lock transitions and decoded text.
        if (!text.empty() || locked != previousLock || processed - lastStatus >= 8000) {
            std::printf("{\"text\":"); quoted(text);
            std::printf(",\"decoder\":\"fldigi MT63\",\"locked\":%s,\"confidence\":%.6f,\"frequencyHz\":%.3f,\"offsetSeconds\":%.4f}\n",
                locked ? "true" : "false", std::isfinite(confidence) ? confidence : 0.0,
                center + (std::isfinite(decoder.TotalFreqOffset()) ? decoder.TotalFreqOffset() : 0.0),
                processed / 8000.0);
            std::fflush(stdout);
            lastStatus = processed;
        }
        previousLock = locked;
    }
};

int main(int argc, char **argv) {
    int bandwidth = 1000;
    bool longInterleave = true;
    double center = 1500;
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--version")) {
            std::printf("RadioWorkbench MT63 / fldigi %s / GPL-3.0-or-later\n", revision);
            return 0;
        }
        if (i + 1 >= argc) { std::fprintf(stderr, "Missing MT63 option value\n"); return 2; }
        const char *option = argv[i++], *value = argv[i];
        double parsed = 0;
        if (!std::strcmp(option, "--bandwidth") && number(value, parsed) &&
            (parsed == 500 || parsed == 1000 || parsed == 2000)) bandwidth = static_cast<int>(parsed);
        else if (!std::strcmp(option, "--interleave") &&
            (!std::strcmp(value, "short") || !std::strcmp(value, "long"))) longInterleave = !std::strcmp(value, "long");
        else if (!std::strcmp(option, "--center-hz") && number(value, parsed)) center = parsed;
        else { std::fprintf(stderr, "Invalid MT63 option: %s\n", option); return 2; }
    }
    if (center < 1000 || center > 2500 || center - bandwidth / 2.0 <= 0 || center + bandwidth / 2.0 >= 4000) {
        std::fprintf(stderr, "MT63 center must be 1000..2500 Hz with the complete occupied band inside 0..4000 Hz\n"); return 2;
    }
    try {
        Receiver receiver(center, bandwidth, longInterleave);
        // Keep byte fragments between POSIX reads; pipe writers may split floats.
        unsigned char bytes[1024];
        size_t retained = 0;
        for (;;) {
            const ssize_t received = ::read(STDIN_FILENO, bytes + retained, sizeof(bytes) - retained);
            if (received < 0) { if (errno == EINTR) continue; std::perror("MT63 stdin"); return 3; }
            if (!received) break;
            const size_t available = retained + static_cast<size_t>(received);
            const size_t count = available / sizeof(float);
            float samples[256];
            std::memcpy(samples, bytes, count * sizeof(float));
            if (count) receiver.process(samples, count);
            retained = available - count * sizeof(float);
            std::memmove(bytes, bytes + count * sizeof(float), retained);
        }
        if (retained) { std::fprintf(stderr, "Truncated float32 sample at end of MT63 input\n"); return 3; }
        // Do not synthesize an unlimited EOF tail: a real MT63 transmitter must
        // flush its interleaver. Padding here would risk inventing trailing text.
    } catch (const std::bad_alloc &) {
        std::fprintf(stderr, "MT63 allocation or DSP processing failed\n"); return 4;
    }
    return 0;
}
