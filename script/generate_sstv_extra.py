#!/usr/bin/env python3
"""Independent Robot36/PD50 mathematical fixtures from N7CXI Dayton 2000.
Does not read application decoder code. Python standard library only.
"""
import argparse, json, math, hashlib
from pathlib import Path
from generate_image_fixtures import FMAudio, vis_header, png, save_wav, COLORS, GRAY

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=Path('/tmp/radio-image-extra'))
OUT=parser.parse_args().output
OUT.mkdir(parents=True, exist_ok=True)
SOURCE='https://www.classicsstv.com/downloads/daytonpaper.pdf'
def rows(h):
    return [[(GRAY[x//40],)*3 if y<16 else (COLORS[x//40] if y<h-16 else COLORS[7-x//40]) for x in range(320)] for y in range(h)]
def ycc(rgb):
    r,g,b=rgb
    return (16.0+.003906*(65.738*r+129.057*g+25.064*b),
            128.0+.003906*(112.439*r-94.154*g-18.285*b),
            128.0+.003906*(-37.945*r-74.494*g+112.439*b))
def scan(a,vals,ns):
    for bar in range(8):
        a.tone(ns//8,1500+800*vals[bar]/255)
def encode(mode,phase):
    h=256 if mode=='pd50' else 240
    original=rows(h)
    image=[[ycc(row[bar*40]) for bar in range(8)] for row in original]
    a=FMAudio(8000,phase)
    bits,parity=vis_header(a,93 if mode=='pd50' else 8)
    start=a.duration_ns
    for y in range(0,h,2):
        chroma=[[.5*(image[y][bar][c]+image[y+1][bar][c]) for bar in range(8)] for c in (1,2)]
        if mode=='pd50':
            a.tone(20_000_000,1200); a.tone(2_080_000,1500)
            scan(a,[p[0] for p in image[y]],91_520_000)
            scan(a,chroma[0],91_520_000)
            scan(a,chroma[1],91_520_000)
            scan(a,[p[0] for p in image[y+1]],91_520_000)
        else:
            for n in range(2):
                a.tone(9_000_000,1200); a.tone(3_000_000,1500)
                scan(a,[p[0] for p in image[y+n]],88_000_000)
                a.tone(4_500_000,1500 if n==0 else 2300)
                a.tone(1_500_000,1900)
                scan(a,chroma[n],44_000_000)
    return a,original,{
        'mode':mode,'vis_code':93 if mode=='pd50' else 8,'width':320,'height':h,
        'vis_bits_lsb_first':bits,'vis_even_parity':parity,'calibration_and_vis_seconds':.91,
        'sync_hz':1200,'video_hz':[1500,2300],'color_model':'BT.601 limited-range Y, R-Y, B-Y from N7CXI AppendixB',
        'pair_sequence':'Y0,CrAverage,CbAverage,Y1' if mode=='pd50' else 'Y0,CrAverage; Y1,CbAverage',
        'sync_ms':20 if mode=='pd50' else 9,'porch_ms':2.08 if mode=='pd50' else 3,
        'scan_ms':91.52 if mode=='pd50' else {'Y':88,'C':44},
        'image_payload_seconds':(a.duration_ns-start)/1e9,
        'row_pair_count':h//2,'image_start_seconds_relative_to_signal':start/1e9,
        'source':{'url':SOURCE,'pages':'5,9-10,14 (one-based)','title':'JL Barber N7CXI Proposal for SSTV Mode Specifications, Dayton2000'},
        'pattern':'Eight RGB bars, sixteen grayscale rows at start, sixteen reversed-color rows at end; each pair shares identical chroma',
        'expected_png':f'sstv_{mode}_expected_320x{h}.png',
        'expected_tolerance_note':'PNG is original RGB. Published rounded BT.601 coefficients introduce small differences after inverse conversion; compare patch medians within5 bytes per channel, excluding edges.',
    }
manifest={'schema_version':1,'source_verification_date':'2026-10-13','generator':str(Path(__file__).resolve()),
          'provenance':'Independent public protocol mathematics. No RadioWorkbench code consulted.',
          'no_decoder_code_used':True,'no_playback_or_hardware':True,'fixtures':[]}
for mode in ['pd50','robot36']:
    for variant,silence,phase in [('clean',.5,.123),('offset',.37319,1.23456789)]:
        a,original,protocol=encode(mode,phase)
        imagepath=OUT/protocol['expected_png']
        if not imagepath.exists(): png(imagepath,320,len(original),[[b for p in row for b in p] for row in original],rgb=True)
        item=save_wav(OUT/f'sstv_{mode}_8000_mono_{variant}.wav',a.samples,8000,silence)
        item.update({'carrier_phase_radians':phase,'variant':variant,'protocol':protocol})
        item['picture_start_seconds_absolute']=item['initial_silence_seconds']+.91
        manifest['fixtures'].append(item)
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'output':str(OUT),'fixtures':len(manifest['fixtures']),'durations':[x['protocol']['image_payload_seconds'] for x in manifest['fixtures']]},indent=2))
