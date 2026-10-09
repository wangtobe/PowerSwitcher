import importlib.util, json, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ['POWER_TEST_STATE']); s=json.loads(p.read_text()); args=sys.argv[1:]
if args==['-g','custom']:
 for name, keys in s['profiles'].items():
  print(name+':')
  for k,v in keys.items(): print(' '+k+' '+str(v))
elif args==['-g']:
 print('System-wide power settings:')
 if 'disabled' in s: print(' SleepDisabled '+str(s['disabled']))
else:
 s['calls']=s.get('calls',0)+1
 if s.get('fail')==s['calls']:
  p.write_text(json.dumps(s)); sys.exit(1)
 if args[0]=='-a': s['disabled']=int(args[2])
 else:
  section={'-c':'AC Power','-b':'Battery Power','-u':'UPS Power'}[args[0]]
  assert section in s['profiles']
  for k,v in zip(args[1::2],args[2::2]):
   if k=='ttyskeepawake': assert k in s['profiles'][section]
   s['profiles'][section][k]=int(v)
 p.write_text(json.dumps(s))
'''
class PowerTests(unittest.TestCase):
 def execute(self,state,mode='normal',timers=''):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d); mock=root/'pmset'; mock.write_text(MOCK); mock.chmod(0o755)
   data=root/'state.json';data.write_text(json.dumps(state))
   script='mode='+mode+'\n'+timers+(ROOT/'Scripts/power.sh').read_text().replace('/usr/bin/pmset',str(mock))
   result=subprocess.run(['/bin/sh','-c',script],capture_output=True,text=True,env={**os.environ,'POWER_TEST_STATE':str(data)})
   return result,json.loads(data.read_text())
 def test_laptop_both_modes(self):
  state={'profiles':{'AC Power':{'sleep':0,'ttyskeepawake':1},'Battery Power':{'sleep':1,'ttyskeepawake':1}},'disabled':1}
  r,s=self.execute(state);self.assertEqual(r.returncode,0,r.stderr)
  self.assertEqual(s['profiles']['Battery Power']['sleep'],5);self.assertEqual(s['disabled'],0)
  r,s=self.execute(s,'task');self.assertEqual(r.returncode,0,r.stderr)
  self.assertEqual(s['profiles'],state['profiles']);self.assertEqual(s['disabled'],1)
 def test_desktop_without_battery_tty_or_global_key(self):
  r,s=self.execute({'profiles':{'AC Power':{'sleep':10}}})
  self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(s['profiles'],{'AC Power':{'sleep':15}})
 def test_ups(self):
  r,s=self.execute({'profiles':{'UPS Power':{'sleep':10}},'disabled':0},'task')
  self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(s['profiles']['UPS Power']['sleep'],0)
 def test_failure_rolls_back(self):
  initial={'profiles':{'AC Power':{'sleep':7,'ttyskeepawake':1},'Battery Power':{'sleep':3,'ttyskeepawake':0}},'disabled':0,'fail':2}
  r,s=self.execute(initial);self.assertNotEqual(r.returncode,0)
  self.assertEqual(s['profiles'],initial['profiles']);self.assertEqual(s['disabled'],0)
 def test_global_failure_rolls_back(self):
  initial={'profiles':{'AC Power':{'sleep':7}},'disabled':0,'fail':2}
  r,s=self.execute(initial,'task');self.assertNotEqual(r.returncode,0)
  self.assertEqual(s['profiles'],initial['profiles']);self.assertEqual(s['disabled'],0)
 def test_invalid_snapshot_does_not_mutate(self):
  r,s=self.execute({'profiles':{'AC Power':{'sleep':'bad'}},'disabled':0})
  self.assertNotEqual(r.returncode,0);self.assertNotIn('calls',s)
 def test_unsupported_profile_does_not_mutate(self):
  r,s=self.execute({'profiles':{},'disabled':0})
  self.assertNotEqual(r.returncode,0);self.assertNotIn('calls',s)
 def test_unknown_mode(self):
  r,s=self.execute({'profiles':{}},'bad')
  self.assertEqual(r.returncode,2);self.assertNotIn('calls',s)
 def test_user_daily_timers(self):
  state={'profiles':{'AC Power':{'sleep':0},'Battery Power':{'sleep':1},'UPS Power':{'sleep':0}},'disabled':1}
  r,s=self.execute(state,timers='daily_ac=30\ndaily_battery=10\n');self.assertEqual(r.returncode,0,r.stderr)
  self.assertEqual({k:v['sleep'] for k,v in s['profiles'].items()},{'AC Power':30,'Battery Power':10,'UPS Power':30})
  self.assertEqual(s['disabled'],0)
 def test_task_mode_ignores_daily_timers(self):
  state={'profiles':{'AC Power':{'sleep':15},'Battery Power':{'sleep':5}},'disabled':0}
  r,s=self.execute(state,'task','daily_ac=30\ndaily_battery=10\n');self.assertEqual(r.returncode,0,r.stderr)
  self.assertEqual(s['profiles'],{'AC Power':{'sleep':0},'Battery Power':{'sleep':1}});self.assertEqual(s['disabled'],1)
 def test_invalid_timers_do_not_mutate(self):
  for timers in ('daily_ac=0\n','daily_ac=181\n','daily_battery=abc\n','daily_ac=-5\n'):
   r,s=self.execute({'profiles':{'AC Power':{'sleep':7}},'disabled':0},timers=timers)
   self.assertEqual(r.returncode,2,timers);self.assertNotIn('calls',s,timers)
 def test_generated_swift_embeds_script_once(self):
  spec=importlib.util.spec_from_file_location('build',ROOT/'Scripts/build.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
  with tempfile.TemporaryDirectory() as d:
   out=Path(d)/'PowerScripts.swift';build.generate(out);text=out.read_text()
  self.assertIn('static let body = #"""\n'+(ROOT/'Scripts/power.sh').read_text()+'"""#',text)
  self.assertNotIn('mode=',text.split('#"""')[0])
