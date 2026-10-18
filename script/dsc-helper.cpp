// Experimental standalone PCM adapter for SDRangel's GPL-3.0-or-later DSC core.
// Copyright (C) 2023 Jon Beniston, M7RCE <jon@beniston.com>
// Adaptation for RadioWorkbench, 2026. See Vendor/DSC/LOCAL-CHANGES.md.
// This program is free software under GPL version 3 or (at your option) later.
// No warranty. The complete license is in Vendor/DSC/COPYING.
#include "decoder.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>
#include <unistd.h>

extern bool frameValid(const std::vector<signed char>&);

struct Options {
    bool vhf=false, invert=false, bits=false, emitInvalid=false, deemphasized=false;
    int rate=48000;
    double center=1700;
};

static std::string digits(const std::vector<signed char>& v, size_t at) {
    if(at+5>v.size()) return "";
    std::string s;
    for(size_t i=at;i<at+5;i++) {
        int n=v[i]; if(n<0 || n>99) return "";
        s += char('0'+n/10); s += char('0'+n%10);
    }
    // Do not invent an equipment/MMSI suffix for a nonzero tenth digit.
    if(s.back()!='0') return s.substr(0,9)+"-"+s.back();
    return s.substr(0,9);
}

class Framer {
    Options opt;
    DSCDecoder decoder;
    uint32_t shift=0;
    int n=0;
    bool locked=false;
    DSCDecoder::SoftBits soft{};
    static constexpr std::array<uint32_t,10> patterns={
        0b101111100111110110011011111001,
        0b111101100110111110010111011010,
        0b101111100101110110101011111001,
        0b011101101010111110011011011010,
        0b101111100110110110101011111001,
        0b101101101010111110010011011011,
        0b101111100100110110111011111001,
        0b001101101110111110011101011010,
        0b101111100111010110101011111001,
        0b110101101010111110010101011011
    };
    void publish(const std::vector<signed char>& v) {
        bool valid=frameValid(v);
        if(!valid && !opt.emitInvalid) return;
        std::string from,to;
        int fmt=v.empty()?-1:v[0];
        size_t self=(fmt==112)?2:((fmt==116)?3:8);
        from=digits(v,self);
        if(fmt==120 || fmt==114 || fmt==123) to=digits(v,2);
        int rx=-1,tx=-1;
        if(fmt==120 && v.size()==23 && v[15]==90 && v[16]>=0 && v[16]<=99 && v[17]>=0 && v[17]<=99)rx=v[16]*100+v[17];
        if(fmt==120 && v.size()==23 && v[18]==90 && v[19]>=0 && v[19]<=99 && v[20]>=0 && v[20]<=99)tx=v[19]*100+v[20];
        std::cout << "{\"schema\":\"rw-dsc-prototype/1\",\"protocol\":\"DSC\",\"experimental\":true,\"interpretation\":\"partial\",\"variant\":\""
                  <<(opt.vhf?"vhf":"mf-hf")<<"\",\"ecc_ok\":"<<(valid?"true":"false")
                  <<",\"invert\":"<<(opt.invert?"true":"false")<<",\"format\":"<<fmt
                  <<",\"origin\":\""<<from<<"\",\"destination\":\""<<to<<"\",\"symbol_errors\":"<<decoder.getErrors()
                  <<",\"corrected_symbols\":null,\"position\":null,\"rx_channel\":"<<(rx<0?"null":std::to_string(rx))
                  <<",\"tx_channel\":"<<(tx<0?"null":std::to_string(tx))
                  <<",\"text\":\"DSC "<<(opt.vhf?"VHF":"MF/HF")<<" "<<from<<" > "<<to<<" ECC "<<(valid?"OK":"FAIL")<<"; partial interpretation\""
                  <<",\"symbols\":[";
        for(size_t i=0;i<v.size();++i) {if(i)std::cout<<',';std::cout<<int(v[i]);}
        std::cout << "]}" << std::endl;
    }
public:
    explicit Framer(Options o):opt(o) {}
    bool isLocked() const {return locked;}
    void push(float s) {
        if(opt.invert)s=-s;
        shift=(shift<<1)|(s>0);
        if(locked && !decoder.isPhasing()) {
            for(size_t i=0;i<patterns.size();++i) {
                if((shift&0x3fffffff)==patterns[i]) {
                    decoder.init(9-int(i));n=0;return;
                }
            }
        }
        if(locked) {
            soft[n++]=s;
            if(n==10) {
                n=0;
                if(decoder.decodeSoftBits(soft)) {
                    publish(decoder.getMessage());locked=false;n=0;
                }
            }
            return;
        }
        if(n<30)++n;
        if(n<30)return;
        // Strict three-character phasing: two DX + one RX or the converse.
        for(size_t i=0;i<patterns.size();++i) {
            if((shift&0x3fffffff)==patterns[i]) {
                decoder.init(9-int(i));locked=true;n=0;break;
            }
        }
    }
};

class AudioDecoder {
    struct Tone {
        std::vector<std::complex<double>> ring;
        std::complex<double> phase{1,0},step,sum{0,0};
        size_t pos=0;
        Tone(int n,double hz,int rate):ring(n),step(std::polar(1.0,-2*acos(-1.0)*hz/rate)) {}
        double sample(double v) {
            auto mix=phase*v;
            sum+=mix-ring[pos];ring[pos]=mix;pos=(pos+1)%ring.size();phase*=step;
            return std::abs(sum)/ring.size();
        }
    };
    Options opt;
    Framer frame;
    Tone low,high;
    double spb,clock;
    bool prev=false;
public:
    explicit AudioDecoder(Options o):opt(o),frame(o),
      low(o.rate/(o.vhf?1200:100),o.vhf?1300:o.center-85,o.rate),
      high(o.rate/(o.vhf?1200:100),o.vhf?2100:o.center+85,o.rate),
      spb(o.rate/double(o.vhf?1200:100)),clock(-spb/2) {}
    void push(int16_t pcm) {
        double lo=low.sample(pcm/32768.0),hi=high.sample(pcm/32768.0);
        if(opt.vhf && !opt.deemphasized) {lo/=1300;hi/=2100;}
        double diff=lo-hi;
        bool bit=diff>0;
        if(bit!=prev)clock-=clock*(frame.isLocked()?0.05:0.2);
        prev=bit;clock+=1;
        if(clock>=spb/2-1) {frame.push(float(diff));clock-=spb;}
    }
};

int main(int argc,char**argv) {
    Options o;
    try {
    for(int i=1;i<argc;i++) {
        std::string s=argv[i];
        if(s=="--variant" && i+1<argc) {std::string p=argv[++i];if(p!="mf-hf"&&p!="vhf")return 2;o.vhf=p=="vhf";}
        else if(s=="--rate" && i+1<argc)o.rate=std::stoi(argv[++i]);
        else if(s=="--center-hz" && i+1<argc)o.center=std::stod(argv[++i]);
        else if(s=="--bits")o.bits=true;
        else if(s=="--inverted")o.invert=true;
        else if(s=="--emit-invalid")o.emitInvalid=true;
        else if(s=="--deemphasized")o.deemphasized=true;
        else {std::cerr<<"dsc-prototype --variant mf-hf|vhf --rate 48000 [--center-hz 1700] [--inverted] [--deemphasized] [--bits] [--emit-invalid]\n";return 2;}
    }
    } catch(...) {std::cerr<<"invalid numeric option\n";return 2;}
    int baud=o.vhf?1200:100;
    if(o.rate<8000||o.rate>192000||o.rate%baud) {std::cerr<<"rate must be 8000..192000 and divisible by profile baud\n";return 2;}
    if(!std::isfinite(o.center)||o.center<100||o.center+85>=o.rate/2.0) {std::cerr<<"invalid center frequency\n";return 2;}
    Framer bits(o);AudioDecoder audio(o);
    std::array<unsigned char,4096> buf{};
    int pending=-1;
    for(;;) {
        ssize_t count=read(STDIN_FILENO,buf.data(),buf.size());
        if(count<0)return 3;
        if(count==0)break;
        for(ssize_t i=0;i<count;i++) {
            unsigned c=buf[i];
            if(o.bits) {if(c=='0'||c=='1')bits.push(c=='1'?1:-1);continue;}
            if(pending<0)pending=int(c);
            else {audio.push(int16_t(uint16_t(pending)|(uint16_t(c)<<8)));pending=-1;}
        }
    }
    if(pending>=0) {std::cerr<<"incomplete PCM16 sample\n";return 4;}
    return 0;
}
