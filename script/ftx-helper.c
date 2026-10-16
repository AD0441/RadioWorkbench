// RadioWorkbench adapter for kgoba/ft8_lib (MIT). Float32 mono, 12000 Hz stdin.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ft8/decode.h>
#include <ft8/message.h>
#include <common/monitor.h>
static void quoted(const char *s) { putchar('"'); for (; *s; s++) { unsigned char c=*s; if(c=='"'||c=='\\') putchar('\\'); if(c>=32 && c<127) putchar(c); else printf("\\u%04x",c); } putchar('"'); }
static void decode(monitor_t *m) {
    ftx_candidate_t c[140]; ftx_message_t seen[50]; int nseen=0;
    int count=ftx_find_candidates(&m->wf,140,c,10);
    for(int i=0;i<count && nseen<50;i++) {
        ftx_message_t msg; ftx_decode_status_t status;
        if(!ftx_decode_candidate(&m->wf,&c[i],25,&msg,&status)) continue;
        int duplicate=0; for(int j=0;j<nseen;j++) if(!memcmp(seen[j].payload,msg.payload,sizeof(msg.payload))) duplicate=1;
        if(duplicate) continue;
        seen[nseen++]=msg;
        char text[FTX_MAX_MESSAGE_LENGTH]; ftx_message_offsets_t offsets;
        if(ftx_message_decode(&msg,NULL,text,&offsets)!=FTX_MESSAGE_RC_OK) continue;
        double hz=(m->min_bin+c[i].freq_offset+(double)c[i].freq_sub/m->wf.freq_osr)/m->symbol_period;
        double seconds=(c[i].time_offset+(double)c[i].time_sub/m->wf.time_osr)*m->symbol_period;
        printf("{\"text\":"); quoted(text);
        printf(",\"frequencyHz\":%.3f,\"offsetSeconds\":%.4f,\"syncScore\":%d,\"crcValid\":true}\n",hz,seconds,c[i].score); fflush(stdout);
    }
}
int main(int argc,char **argv) {
    ftx_protocol_t protocol=(argc==2 && !strcmp(argv[1],"ft4"))?FTX_PROTOCOL_FT4:FTX_PROTOCOL_FT8;
    monitor_config_t config={.f_min=100,.f_max=3500,.sample_rate=12000,.time_osr=2,.freq_osr=2,.protocol=protocol};
    monitor_t mon; monitor_init(&mon,&config);
    int limit=12000*(protocol==FTX_PROTOCOL_FT4?7.5:15), total=0;
    float *block=calloc(mon.block_size,sizeof(float)); if(!block) return 2;
    size_t n;
    while(total<limit && (n=fread(block,sizeof(float),mon.block_size,stdin))>0) {
        for(size_t i=0;i<n;i++) if(!isfinite(block[i])) block[i]=0;
        total+=(int)n;
        if(n<(size_t)mon.block_size) memset(block+n,0,(mon.block_size-n)*sizeof(float));
        monitor_process(&mon,block);
    }
    if(total>12000) decode(&mon);
    monitor_free(&mon); free(block); return ferror(stdin)?3:0;
}
