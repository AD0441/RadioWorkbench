#!/usr/bin/env python3
"""Isolated DSC checks; no capture, application launch, network, or installation.

Optional public WAVs are read only from explicit paths. Do not bundle them without
checking their redistribution terms. Synthetic modulation is not independent RF.
"""
import argparse
import array
import hashlib
import json
import math
import pathlib
import random
import select
import subprocess
import sys
import time
import wave

DISTRESS = [112,112,25,58,5,99,70,107,4,52,60,13,7,12,52,109,127,52]
INDIVIDUAL = [120,120,23,33,33,33,40,100,20,14,44,55,50,100,126,90,0,8,90,0,8,117,94]

def encoded(v):
    zeros = 7 - v.bit_count()
    return [(v >> j) & 1 for j in range(7)] + [(zeros >> j) & 1 for j in (2,1,0)]

def bits(msg, variant, corrupt_dx=None, phasing=True):
    chars=[]
    for k in range(6+len(msg)+2):
        dx=125 if k<6 else (msg[k-6] if k<6+len(msg) else msg[-2])
        rx=111-k if k<8 else (msg[k-8] if k<8+len(msg) else msg[-2])
        if k<6 and not phasing:dx=rx=0
        a=encoded(dx)
        if k==corrupt_dx:a[7]^=1
        chars.extend(a+encoded(rx))
    return [j%2 for j in range(20 if variant=='vhf' else 200)] + chars

def pcm(bits,variant):
    rate=48000;baud=1200 if variant=='vhf' else 100;n=rate//baud
    low,high=(1300,2100) if variant=='vhf' else (1615,1785)
    phase=.37;out=array.array('h',[0]*2400)
    for bit in bits:
        freq=low if bit else high
        # Flat VHF discriminator audio preserves transmitter pre-emphasis.
        amp=8000*(freq/1700 if variant=='vhf' else 1)
        step=2*math.pi*freq/rate
        for _ in range(n):
            phase+=step;out.append(round(amp*math.sin(phase)))
    out.extend([0]*2400)
    if sys.byteorder!='little':out.byteswap()
    return out.tobytes()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--helper',default='/tmp/rw-dsc-audit/dsc-prototype')
    ap.add_argument('--vhf-wav');ap.add_argument('--hf-wav');ap.add_argument('--output',default='/tmp/rw-dsc-audit/validation.json')
    a=ap.parse_args();results=[]
    def run(data,variant='vhf',extra=(),expect_code=0):
        p=subprocess.run([a.helper,'--variant',variant,'--rate','48000',*extra],input=data,capture_output=True,timeout=10)
        assert p.returncode==expect_code,(p.returncode,p.stderr.decode())
        return [json.loads(l) for l in p.stdout.splitlines()]
    def check(name,fn):
        t=time.monotonic();detail=fn();results.append({'name':name,'passed':True,'seconds':round(time.monotonic()-t,4),'details':detail})
    def expect(data,variant='vhf',count=1,extra=()):
        out=run(data,variant,extra);assert len(out)==count,out
        assert all(x['ecc_ok'] and x['interpretation']=='partial' and x['position'] is None for x in out)
        return out
    vb=bits(INDIVIDUAL,'vhf');hb=bits(DISTRESS,'mf-hf')
    vp=pcm(vb,'vhf');hp=pcm(hb,'mf-hf')
    check('external-symbol-oracle-distress',lambda:expect(''.join(map(str,hb)).encode(),'mf-hf',extra=['--bits']))
    check('synthetic-vhf-audio',lambda:expect(vp))
    check('synthetic-mfhf-audio',lambda:expect(hp,'mf-hf'))
    check('time-diversity-recovers-bad-dx',lambda:expect(''.join(map(str,bits(INDIVIDUAL,'vhf',corrupt_dx=8))).encode(),extra=['--bits']))
    bad=INDIVIDUAL.copy();bad[-1]^=1
    check('wrong-ecc-rejected',lambda:expect(pcm(bits(bad,'vhf'),'vhf'),count=0))
    check('missing-phasing-rejected',lambda:expect(pcm(bits(INDIVIDUAL,'vhf',phasing=False),'vhf'),count=0))
    check('truncated-frame-rejected',lambda:expect(vp[:len(vp)//2],count=0))
    check('two-frames-on-one-stream',lambda:expect(vp+vp,count=2))
    check('silence-after-frame-no-phantoms',lambda:expect(vp+b'\0'*(48000*2*3)))
    check('silence-alone-no-frames',lambda:expect(b'\0'*(48000*2*5),count=0))
    rng=random.Random(493);noise=array.array('h',(rng.randint(-1000,1000) for _ in range(48000*2)))
    if sys.byteorder!='little':noise.byteswap()
    check('seeded-noise-no-frames',lambda:expect(noise.tobytes(),count=0))
    check('wrong-profile-no-frame',lambda:expect(vp,'mf-hf',count=0))
    check('odd-byte-pcm-rejected',lambda:run(b'\0',expect_code=4))
    check('nonfinite-center-rejected',lambda:run(b'',extra=['--center-hz','nan'],expect_code=2))
    check('invalid-rate-rejected',lambda:run(b'',extra=['--rate','bad'],expect_code=2))
    def live():
        p=subprocess.Popen([a.helper,'--variant','vhf'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            for at in range(0,len(vp),137):p.stdin.write(vp[at:at+137]);p.stdin.flush()
            assert select.select([p.stdout],[],[],2)[0],'stdout retained while input open'
            msg=json.loads(p.stdout.readline());assert msg['destination']=='233333334' and msg['ecc_ok']
            p.terminate();p.wait(timeout=2)
            return {'received_before_eof':True,'odd_chunk_bytes':137,'terminated_with_stdin_open':True}
        finally:
            if p.poll() is None:p.kill();p.wait()
    check('fragmented-live-flush-cancel',live)
    if a.vhf_wav:
        def offair_vhf():
            p=pathlib.Path(a.vhf_wav)
            with wave.open(str(p)) as w:
                assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,48000)
                out=expect(w.readframes(w.getnframes()))
            m=out[0];assert (m['origin'],m['destination'],m['rx_channel'],m['tx_channel'])==('201444555','233333334',8,8),m
            return {'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'oracle':'SDRangel issue #1707 author: source/destination/channel','messages':out}
        check('external-vhf-audio-and-author-fields',offair_vhf)
    if a.hf_wav:
        def offair_hf():
            # Local optional NumPy resampling: explicit mono selection, linear 88.2k->48k.
            # This is fixture preparation, not the application resampler benchmark.
            import numpy as np
            p=pathlib.Path(a.hf_wav)
            with wave.open(str(p)) as w:
                assert w.getsampwidth()==2
                x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').reshape(-1,w.getnchannels())[:,0]
                rate=w.getframerate()
            y=np.interp(np.arange(int(len(x)*48000/rate))*rate/48000,np.arange(len(x)),x)
            out=run(np.clip(y,-32768,32767).astype('<i2').tobytes(),'mf-hf',['--center-hz','500'])
            assert len(out)==5 and all(m['ecc_ok'] for m in out),out
            return {'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'fixture_input_rate':rate,'mono_channel':0,'center_hz':500,'valid_calls':len(out),'oracle_limit':'Independent recorded audio with valid ECC; message count and fields are observed regression baselines, not externally certified completeness.','messages':out}
        check('external-mfhf-audio-five-ecc-valid-calls',offair_hf)
    summary={'schema':'rw-dsc-prototype-validation/1','status':'experimental, not integrated','helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'passed':len(results),'failed':0,'checks':results}
    pathlib.Path(a.output).write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'passed':len(results),'failed':0,'output':a.output}))

if __name__=='__main__':main()
