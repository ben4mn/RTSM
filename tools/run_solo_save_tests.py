#!/usr/bin/env python3
"""Fresh Godot processes share one isolated device save; user's files are untouched."""
import json,os,tempfile,uuid
from pathlib import Path
from run_focused_tests import freeze_project,run_case
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parent/'solo-save-tests'
OUT.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='pocket-solo-save-') as folder:
 project=Path(folder)
 freeze_project(project)
 config=(project/'project.godot').read_text(encoding='utf-8')
 user='pocket-solo-save-tests/'+uuid.uuid4().hex
 config=config.replace('[application]',f'[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{user}"',1)
 (project/'project.godot').write_text(config,encoding='utf-8')
 for phase in ['writer','reader','online','corrupt']:
  result=run_case([os.environ['GODOT_BIN'],'--headless','--path',str(project),'res://tools/test_solo_save.tscn','--',f'--phase={phase}'],cwd=project,env=os.environ.copy(),timeout=90)
  text=result.stdout+result.stderr
  (OUT/f'{phase}.log').write_text(text,encoding='utf-8')
  print(text,flush=True)
  if result.returncode or 'SCRIPT ERROR' in text or 'ERROR:' in text: raise SystemExit(f'FAIL {phase}')
 print(json.dumps({'result':'PASS','fresh_processes':4,'private_user_dir':user}),flush=True)
