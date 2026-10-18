// RadioWorkbench standalone adapter. Decoder copyright/licence: Vendor/ALE2G/COPYING.
#include "radio_compat.h"
#include "decode_ff_impl.h"
#include <cerrno>
#include <csignal>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;
static void request_stop(int) { stopping = 1; }

extern "C" void radio_ale_emit(const char *text) {
    // The decoder's messages are bounded ASCII. Escape every JSON control byte;
    // never let a received message create an additional protocol record.
    fputs("{\"mode\":\"ALE2G\",\"decoder\":\"KiwiSDR ALE 2G\",\"text\":\"", stdout);
    for (size_t i = 0; text[i] && i < 1024; ++i) {
        const unsigned char c = text[i];
        if (c == '"' || c == '\\') { fputc('\\', stdout); fputc(c, stdout); }
        else if (c == '\n') fputs("\\n", stdout);
        else if (c == '\r') fputs("\\r", stdout);
        else if (c == '\t') fputs("\\t", stdout);
        else if (c < 32 || c >= 127) fprintf(stdout, "\\u%04x", unsigned(c));
        else fputc(c, stdout);
    }
    fputs("\"}\n", stdout);
    fflush(stdout);
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        puts("RadioWorkbench ALE2G 1; KiwiSDR efb38e2b25137029cb37a96a94e03366f8d2871e; float32 mono 8000 Hz");
        return 0;
    }
    if (argc != 1) { fputs("Usage: ale-helper < float32-mono-8000.pcm\n", stderr); return 2; }
    struct sigaction action{};
    action.sa_handler = request_stop;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, nullptr);
    sigaction(SIGINT, &action, nullptr);
    signal(SIGPIPE, SIG_IGN);

    ale::decode_ff_impl decoder;
    decoder.modem_init(0, false, 8000, 1024, false);
    decoder.set_display(CMDS);
    unsigned char bytes[4096 + sizeof(float)];
    size_t carried = 0;
    float samples[1024];
    while (!stopping) {
        const ssize_t count = read(STDIN_FILENO, bytes + carried, 4096);
        if (count < 0) { if (errno == EINTR) continue; perror("ALE input"); return 1; }
        if (count == 0) break;
        const size_t size = carried + size_t(count);
        const size_t total = size / sizeof(float);
        for (size_t i = 0; i < total; ++i) {
            float sample;
            memcpy(&sample, bytes + i * sizeof(float), sizeof(float));
            samples[i] = std::isfinite(sample) ? std::clamp(sample, -1.0f, 1.0f) * 32767.0f : 0.0f;
        }
        decoder.do_modem(samples, int(total));
        carried = size % sizeof(float);
        if (carried) memmove(bytes, bytes + total * sizeof(float), carried);
        if (ferror(stdout)) return 1;
    }
    decoder.do_modem(nullptr, 0);
    if (carried && !stopping) { fputs("Incomplete float32 sample at end of ALE input\n", stderr); return 2; }
    return ferror(stdout) ? 1 : 0;
}
