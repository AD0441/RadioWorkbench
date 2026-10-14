#!/usr/bin/env python3
"""Transmitter model for JE3HHT's MP/MR/ML/MP-N/MC-N specifications.

Uses the researched primary timing tables, not application decoder code/output.
Headers are calculated directly from mode.txt. Python standard library only.
"""
import argparse
import json
from pathlib import Path
from generate_image_fixtures import FMAudio, png, save_wav, COLORS, GRAY
from generate_sstv_family_fixtures import color_values

SOURCE = 'https://github.com/n5ac/mmsstv/blob/master/mode.txt'


def header(audio, record, bad=False):
    code = record['vis_code']
    if record['identification'] == 'VIS-16-LSB':
        for ms, hz in [(300,1900),(10,1200),(300,1900),(30,1200)]: audio.tone(ms*1_000_000,hz)
        for bit in range(16): audio.tone(30_000_000,1100 if code & (1<<bit) else 1300)
        audio.tone(30_000_000,1500 if bad else 1200)
    else:
        for ms, hz in [(300,1900),(100,2100),(22,1900)]: audio.tone(ms*1_000_000,hz)
        groups = [0b101101,0b010101,code,0b010101 ^ code ^ (1 if bad else 0)]
        for group in groups:
            for bit in reversed(range(6)): audio.tone(22_000_000,1900 if group & (1<<bit) else 2100)


def encode(record, full=False, manual=False, bad=False):
    w,h = record['width'],record['height']
    audio = FMAudio(8000,.731234)
    if not manual: header(audio,record,bad)
    payload_start = audio.duration_ns/1e9
    timing = record['timing_ms']
    narrow = record['identification'] == 'N-VIS-24'
    black,span = (2044,256) if narrow else (1500,800)
    rows = [[(v,v,v) for v in GRAY] if y<16 else COLORS if y<h-16 else list(reversed(COLORS)) for y in range(h)]
    def tone(ms,hz): audio.tone(round(ms*1_000_000),hz)
    def scan(values,ms,hold=False):
        total = round(ms*1_000_000)
        for bar,value in enumerate(values):
            audio.tone(round((bar+1)*total/8)-round(bar*total/8), black+span*value/255)
        if hold: tone(timing['last_pixel_hold'],black+span*values[-1]/255)
    # Bad-header fixtures end before any raster; they test rejection only.
    if not bad:
        if record['family'] in {'MMSSTV-MP','MMSSTV-MPN'}:
            for y in range(0,h,2):
                a,b = [[color_values(c,full) for c in rows[row]] for row in (y,y+1)]
                tone(timing['sync'],1900 if narrow else 1200); tone(timing['porch'],black)
                scan([c[0] for c in a],timing['TW'])
                for channel in (1,2): scan([(x[channel]+z[channel])/2 for x,z in zip(a,b)],timing['TW'])
                scan([c[0] for c in b],timing['TW'])
        elif record['family'] == 'MMSSTV-MRML':
            for row in rows:
                values = [color_values(c,full) for c in row]
                tone(timing['sync'],1200); tone(timing['porch'],black)
                scan([c[0] for c in values],timing['Y'],True)
                for channel in (1,2): scan([c[channel] for c in values],timing['C'],True)
        else:
            for row in rows:
                tone(timing['sync'],1900); tone(timing['porch'],black)
                for channel in range(3): scan([c[channel] for c in row],timing['TW'])
    original = [[c for x in range(w) for c in row[x*8//w]] for row in rows]
    return audio,original,{'mode':record['name'],'width':w,'height':h,'vis':record['vis_code'],
                          'identification':record['identification'],'color_range':'full' if full else 'bt601-limited',
                          'manual':manual,'bad_header':bad,'payload_start_seconds':payload_start,
                          'payload_duration_seconds':audio.duration_ns/1e9-payload_start,
                          'source':SOURCE,'timing_ms':timing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('/tmp/radio-mmsstv-fixtures'))
    args = parser.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    catalog = json.loads((Path(__file__).resolve().parent.parent/'docs/sstv-modes.json').read_text())
    records = [r for r in catalog['modes'] if r['family'] in {'MMSSTV-MP','MMSSTV-MRML','MMSSTV-MPN','MMSSTV-MCN'}]
    cases = [(r,False,False,False) for r in records]
    cases += [(r,True,False,False) for r in records if r['name'] in {'MP73','MR73','MP73-N'}]
    cases += [(r,False,False,True) for r in records if r['name'] in {'MP73','MC110-N'}]
    cases += [(r,False,True,False) for r in records if r['name']=='MP73-N']
    manifest = {'schema_version':1,'date':'2026-10-13','source':SOURCE,
                'generator':'script/generate_mmsstv_fixtures.py','provenance':'Independent mathematical transmitter from primary mode tables and header definitions; no decoder imported',
                'limitations':['Synthetic audio, no RF/transmitter interoperability','Fixtures choose an explicit color range; the timing document does not define universal Y/Cr/Cb scaling'], 'fixtures':[]}
    for record,full,manual,bad in cases:
        audio,original,protocol = encode(record,full,manual,bad)
        variant = 'badheader' if bad else 'manual' if manual else 'fullrange' if full else 'clean'
        name = 'sstv_mmsstv_'+record['name'].lower().replace('-','_')+'_8000_'+variant
        item = save_wav(args.output/(name+'.wav'),audio.samples,8000,.37319)
        protocol['payload_start_seconds'] += item['initial_silence_seconds']
        if bad: protocol['expected_error'] = 'N-VIS inválido' if record['identification']=='N-VIS-24' else 'Stop VIS inválido'
        item['protocol'] = protocol; manifest['fixtures'].append(item)
        if not bad: png(args.output/(name+'.png'),protocol['width'],protocol['height'],original,rgb=True)
    # Classic VIS2 is not N-VIS2, even though both identify a mode by number2.
    for name,code,wrong_parity,error in [
        ('sstv_classic_vis2_8000_unsupported',2,False,'VIS 2: formato todavía no implementado'),
        ('sstv_classic_m1_8000_badparity',44,True,'paridad incorrecta')
    ]:
        a=FMAudio(8000,.731234)
        for ms,hz in [(300,1900),(10,1200),(300,1900),(30,1200)]: a.tone(ms*1_000_000,hz)
        bits=[(code>>b)&1 for b in range(7)]
        for bit in bits+[(sum(bits)%2) ^ int(wrong_parity)]: a.tone(30_000_000,1100 if bit else 1300)
        a.tone(30_000_000,1200)
        item=save_wav(args.output/(name+'.wav'),a.samples,8000,.37319)
        item['protocol']={'mode':'Classic VIS','width':320,'height':256,'color_range':'bt601-limited',
                          'manual':False,'bad_header':True,'payload_start_seconds':0,'expected_error':error,
                          'source':'https://www.classicsstv.com/downloads/daytonpaper.pdf'}
        manifest['fixtures'].append(item)
    (args.output/'mmsstv-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'output':str(args.output),'fixtures':len(manifest['fixtures'])},indent=2))


if __name__=='__main__': main()
