"""Rebuild the licensed short-cue bank from the retained unmodified Kenney samples.
Requires numpy, scipy and soundfile. Sources, licenses and hashes live with assets.
"""
from pathlib import Path
import hashlib,json,shutil
import numpy as np
from scipy.signal import resample_poly, butter, sosfilt
import soundfile as sf
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'assets/audio/kenney'
SOURCE=DEST/'originals'
RATE=22050
CUES={
 'button_click':('interface',['click_001','click_002','click_003'],.15,1),
 'select_unit':('interface',['pluck_001','pluck_002'],.18,.85),
 'command_move':('rpg',['handleSmallLeather','handleSmallLeather2','cloth2'],.30,1),
 'command_attack':('rpg',['drawKnife1','drawKnife2','drawKnife3'],.32,1),
 'attack_hit':('impact',['impactMetal_light_000','impactMetal_light_001','impactPunch_medium_000'],.30,1),
 'unit_death':('rpg',['dropLeather','cloth1','cloth3'],.36,.85),
 'gather_food':('rpg',['cloth1','cloth2','cloth4'],.26,1),
 'gather_wood':('impact',['impactWood_light_000','impactWood_light_001','impactWood_light_002'],.28,1),
 'gather_gold':('impact',['impactMining_000','impactMining_001','impactMining_002'],.32,1),
 'construction_work':('impact',['impactPlank_medium_000','impactPlank_medium_001','impactPlank_medium_002'],.30,1),
 'building_place':('rpg',['bookPlace1','bookPlace2','bookPlace3'],.30,1),
 'building_invalid':('interface',['error_001','error_002'],.25,.85),
 'unit_trained':('interface',['confirmation_001','confirmation_002'],.42,.9),
 'building_complete':('interface',['confirmation_003','confirmation_004'],.50,.9),
 'under_attack':('impact',['impactBell_heavy_000','impactBell_heavy_001'],.75,.7),
 'age_up':('impact',['impactBell_heavy_002','impactBell_heavy_003'],.90,1),
 'victory':('impact',['impactBell_heavy_001','impactBell_heavy_004'],1.18,1),
 'defeat':('impact',['impactBell_heavy_003','impactBell_heavy_004'],1.05,.6),
}

def read_take(path, pitch=1):
 data,sr=sf.read(path,always_2d=True);data=data.mean(axis=1)
 data=resample_poly(data,RATE,sr)
 if pitch!=1:data=np.interp(np.arange(0,len(data),pitch),np.arange(len(data)),data)
 data-=data.mean()
 # Gentle low-pass rounds brittle digital transients, not a synthetic replacement.
 return sosfilt(butter(2,4200,fs=RATE,output='sos'),data)

def fade(data):
 n=min(int(.005*RATE),len(data)//3);data[:n]*=np.linspace(0,1,n)
 n=min(int(.035*RATE),len(data)//3);data[-n:]*=np.linspace(1,0,n)
 return data

def build():
 (DEST/'cues').mkdir(parents=True,exist_ok=True)
 records=[];bank={}
 for cue,(pack,names,seconds,pitch) in CUES.items():
  bank[cue]=[]
  for index,name in enumerate(names):
   source=SOURCE/pack/(name+'.ogg'); data=read_take(source,pitch)
   n=int(seconds*RATE)
   if cue in ('age_up','victory','under_attack'):
    # Distinct short sourced bell phrases; no oscillators/no procedural noise.
    notes={'under_attack':[(0,.7),(.22,.7)],'age_up':[(0,.9),(.25,1.2)],'victory':[(0,1),(.25,1.25),(.5,1.5)]}[cue]
    mix=np.zeros(n)
    for delay,ratio in notes:
     take=fade(read_take(source,ratio)[:int(.6*RATE)]);start=int(delay*RATE);take=take[:n-start];mix[start:start+len(take)]+=take
    data=mix
   else:data=data[:n]
   if len(data)<int(.065*RATE):data=np.pad(data,(0,int(.065*RATE)-len(data)))
   data=fade(data);data*=.48/max(.001,np.abs(data).max())
   path=DEST/'cues'/f'{cue}_{index+1:02d}.wav';sf.write(path,data,RATE,subtype='PCM_16')
   bank[cue].append('res://'+path.relative_to(ROOT).as_posix())
   records.append({'cue':cue,'file':path.relative_to(ROOT).as_posix(),'source':source.relative_to(ROOT).as_posix(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'seconds':round(len(data)/RATE,4),'peak':round(float(abs(data).max()),4)})
 (DEST/'manifest.json').write_text(json.dumps({'license':'CC0-1.0','creator':'Kenney','sample_rate':RATE,'derivation':'Mono, 22.05kHz resample, gentle 4.2kHz low-pass, peak normalized to 0.48, 5ms attack/35ms release; phrases/pitch edits per tools/build_sample_palette.py','samples':records},indent=2)+'\n',encoding='utf-8',newline='\n')
 lines=['extends RefCounted','## Licensed, edited Kenney recordings. Original files and CC0 licenses are retained.','## No synthesis and no gameplay RNG. The manager owns gain, priorities and caps.','','const BANK: Dictionary = {']
 for cue,paths in bank.items():lines.append('\t"'+cue+'": ['+', '.join('preload("'+p+'")' for p in paths)+'],')
 lines+=['}','','','static func build() -> Dictionary:','\treturn BANK.duplicate(true)','']
 (ROOT/'scripts/audio/sample_palette.gd').write_bytes('\n'.join(lines).encode())
 print(f'Built {len(records)} PCM samples for {len(bank)} cues; {sum((ROOT/r["file"]).stat().st_size for r in records)} bytes.')

if __name__=='__main__':build()
