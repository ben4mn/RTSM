#!/usr/bin/env python3
"""Fresh Godot processes share one isolated device save; user's files are untouched."""
import argparse,json,os,re,tempfile,uuid
from pathlib import Path
from run_focused_tests import freeze_project,run_case
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=ROOT.parent/'solo-save-tests')
parser.add_argument('--changed-pacing',action='store_true',help='Change only the isolated reader project defaults after writing the old match')
args=parser.parse_args()
OUT=args.output.resolve()
OUT.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='pocket-solo-save-') as folder:
 project=Path(folder)
 freeze_project(project)
 config=(project/'project.godot').read_text(encoding='utf-8')
 user='pocket-solo-save-tests/'+uuid.uuid4().hex
 config=config.replace('[application]',f'[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{user}"',1)
 (project/'project.godot').write_text(config,encoding='utf-8')
 for phase in ['writer','reader','online','corrupt']:
  if phase=='reader' and args.changed_pacing:
   # Change defaults in the private test copy only, without changing topology,
   # generator identity or the completed writer's device checkpoint.
   path=project/'scripts/data/skirmish_data.gd'
   source,count=re.subn(r'^const SACRED_VICTORY_HOLD_SECONDS: float = [^\n]+', 'const SACRED_VICTORY_HOLD_SECONDS: float = 360.0',path.read_text(encoding='utf-8'),flags=re.M)
   assert count==1,'Sacred default fixture anchor changed'
   path.write_text(source,encoding='utf-8')
   path=project/'scripts/map/map_generator.gd'
   source=path.read_text(encoding='utf-8')
   anchor='return int(_resource_amounts.get(tile, 0))'
   assert source.count(anchor)==1,'Resource default fixture anchor changed'
   path.write_text(source.replace(anchor,anchor+' * 3'),encoding='utf-8')
  result=run_case([os.environ['GODOT_BIN'],'--headless','--path',str(project),'res://tools/test_solo_save.tscn','--',f'--phase={phase}']+(['--changed-pacing'] if args.changed_pacing else []),cwd=project,env=os.environ.copy(),timeout=90)
  text=result.stdout+result.stderr
  (OUT/f'{phase}.log').write_text(text,encoding='utf-8')
  print(text,flush=True)
  if result.returncode or 'SCRIPT ERROR' in text or 'ERROR:' in text: raise SystemExit(f'FAIL {phase}')
 print(json.dumps({'result':'PASS','fresh_processes':4,'changed_reader_defaults':args.changed_pacing,'private_user_dir':user}),flush=True)
