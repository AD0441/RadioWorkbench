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
#include <libacars/acars.h>
#include <libacars/adsc.h>
#include <libacars/arinc.h>
#include <libacars/libacars.h>
#include <libacars/list.h>
#include <libacars/vstring.h>
static la_reasm_ctx *applications;
static unsigned long application_blocks;

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
    // acarsdec removed odd parity after validating parity/CRC. Restore the original
    // parity bits, retaining its original BCS, for libacars' complete block parser.
    uint8_t frame[260];
    for (int i = 0; i < blk->txtlen; i++) {
        uint8_t b = blk->txt.raw[i] & 0x7f;
        frame[i] = b | ((__builtin_popcount((unsigned)b) % 2 == 0) ? 0x80 : 0);
    }
    frame[blk->txtlen] = blk->crc[0]; frame[blk->txtlen+1] = blk->crc[1]; frame[blk->txtlen+2] = 0x7f;
    // Bound reassembly memory even under an indefinitely busy input.
    if (++application_blocks % 1000 == 0) { la_reasm_ctx_destroy(applications); applications = la_reasm_ctx_new(); }
    la_proto_node *node = la_acars_parse_and_reassemble(frame, blk->txtlen + 3, LA_MSG_DIR_UNKNOWN, applications, blk->tv);
    if (node && node->data) {
        la_acars_msg *msg = node->data;
        printf(",\"applicationStatus\":%d", msg->reasm_status);
        if (!msg->err && msg->crc_ok && node->next) {
            la_vstring *j = la_proto_tree_format_json(NULL, node->next), *t = la_proto_tree_format_text(NULL, node->next);
            if (j && j->len <= 65536) { printf(",\"applicationJSON\":"); json_string(j->str, j->len); }
            if (t && t->len <= 65536) { printf(",\"applicationText\":"); json_string(t->str, t->len); }
            la_proto_node *ads = la_proto_tree_find_adsc(node);
            la_proto_node *arinc = la_proto_tree_find_arinc(node);
            if (ads && ads->data && arinc && arinc->data && ((la_arinc_msg *)arinc->data)->crc_ok) {
                la_adsc_msg_t *m = ads->data;
                if (!m->err) for (la_list *l = m->tag_list; l; l = la_list_next(l)) {
                    la_adsc_tag_t *tag = l->data;
                    if (tag->data && (tag->tag == 7 || tag->tag == 9 || tag->tag == 10 || tag->tag == 18 || tag->tag == 19 || tag->tag == 20)) {
                        la_adsc_basic_report_t *r = tag->data;
                        if (isfinite(r->lat) && isfinite(r->lon) && fabs(r->lat)<=90 && fabs(r->lon)<=180)
                            printf(",\"aircraftPosition\":{\"latitude\":%.7f,\"longitude\":%.7f,\"altitudeFeet\":%d}", r->lat, r->lon, r->alt);
                        break;
                    }
                }
            }
            if(j) la_vstring_destroy(j, true); if(t) la_vstring_destroy(t, true);
        }
    }
    la_proto_tree_destroy(node);
    printf(",\"endBlock\":%u,\"parityCorrections\":%u,\"levelDB\":%.2f,\"queueDrops\":%lu}\n",
           (unsigned char)blk->txt.d.text[length - 1], blk->err, isfinite(blk->lvl) ? blk->lvl : -120, atomic_load(&dropped));
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts("RadioWorkbench ACARS helper · acarsdec cbaa28c4173fc1529a01ab50708e29d12d09a644 · GPL-2.0-only"); return 0;
    }
    if (argc != 1) { fputs("Input: mono float32 little-endian PCM, 12000 Hz, stdin\n", stderr); return 2; }
    setvbuf(stdout, NULL, _IOLBF, 0);
    applications = la_reasm_ctx_new();
    la_config_set_int("acars_bearer", LA_ACARS_BEARER_VHF);
    la_config_set_bool("decode_fragments", false);
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
    la_reasm_ctx_destroy(applications);
    printf("{\"event\":\"summary\",\"queueDrops\":%lu}\n", atomic_load(&dropped));
    return failed ? 4 : 0;
}
