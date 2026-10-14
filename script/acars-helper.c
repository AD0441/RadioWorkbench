/* SPDX-License-Identifier: GPL-2.0-only
 * RadioWorkbench stdin adapter for acarsdec. Complete sources ship with the app.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <stdatomic.h>
#include "acarsdec.h"
#include "acars.h"
#include "msk.h"
#include "statsd.h"

runtime_t R = {0};
static _Atomic unsigned long dropped = 0;
void rw_queue_dropped(void) { atomic_fetch_add(&dropped, 1); }
int statsd_update(const char *p, const statsd_metric_t *const m, const unsigned int n) { return 0; }
int statsd_inc_per_channel(int channel, const char *name) { return 0; }

static void json_string(const char *data, size_t length) {
    putchar('"');
    for (size_t i = 0; i < length; i++) {
        unsigned char c = data[i];
        if (c == '"' || c == '\\') { putchar('\\'); putchar(c); }
        else if (c < 32 || c >= 127) printf("\\u%04x", c);
        else putchar(c);
    }
    putchar('"');
}
void outputmsg(const msgblk_t *blk) {
    int length = blk_textlen(blk);
    if (length < 1 || length > (int)sizeof(blk->txt.d.text)) return;
    printf("{\"timestamp\":%.6f,\"mode\":", blk->tv.tv_sec + blk->tv.tv_usec / 1000000.0);
    json_string(&blk->txt.d.mode, 1);
    printf(",\"registration\":"); json_string(blk->txt.d.addr, 7);
    printf(",\"ack\":"); json_string(&blk->txt.d.ack, 1);
    printf(",\"label\":"); json_string(blk->txt.d.label, 2);
    printf(",\"block\":"); json_string(&blk->txt.d.bid, 1);
    printf(",\"payload\":"); json_string(blk->txt.d.text, length - 1);
    printf(",\"endBlock\":%u,\"parityCorrections\":%u,\"levelDB\":%.2f,\"queueDrops\":%lu}\n",
           (unsigned char)blk->txt.d.text[length - 1], blk->err, isfinite(blk->lvl) ? blk->lvl : -120, atomic_load(&dropped));
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts("RadioWorkbench ACARS helper · acarsdec cbaa28c4173fc1529a01ab50708e29d12d09a644 · GPL-2.0-only"); return 0;
    }
    if (argc != 1) { fputs("Input: mono float32 little-endian PCM, 12000 Hz, stdin\n", stderr); return 2; }
    setvbuf(stdout, NULL, _IOLBF, 0);
    channel_t channel = {0}; float samples[4096];
    R.channels = &channel; R.nbch = 1; R.running = true;
    channel.dm_buffer = samples;
    if (initMsk(&channel) || initAcars(&channel)) return 3;
    size_t count;
    while ((count = fread(samples, sizeof(float), 4096, stdin)) > 0) {
        for (size_t i = 0; i < count; i++) samples[i] = isfinite(samples[i]) ? samples[i] / 2 : 0;
        demodMSK(&channel, (int)count);
    }
    int failed = ferror(stdin);
    deinitAcars(); free(channel.inb); free(channel.blk);
    printf("{\"event\":\"summary\",\"queueDrops\":%lu}\n", atomic_load(&dropped));
    return failed ? 4 : 0;
}
