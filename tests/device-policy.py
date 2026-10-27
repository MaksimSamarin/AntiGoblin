#!/usr/bin/env python3
"""Exercise the actual shell policy controller against a disposable native CLI."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['POLICY_FIXTURE']);s=json.loads(p.read_text());c=sys.argv[-1];a=c.split()
def save(): p.write_text(json.dumps(s))
if s.get('fail') and s['fail'] in c:
 s.pop('fail');save();sys.exit(1)
if c=='show running-config':
 print('interface Bridge0\n    rename Home\n    up\n!')
 for wan in s['wans']:print('interface '+wan+'\n    ip global 700\n    up\n!')
 for name,v in s['policies'].items():
  print('ip policy '+name+'\n    description '+v['description'])
  for wan in v.get('wans',[]):print('    permit global '+wan)
  print('!')
 print('ip hotspot')
 for name,v in s['bindings'].items():print('    policy '+name+' '+v)
 for mac,v in s['hosts'].items():
  if v.get('policy'):print('    host '+mac+' policy '+v['policy'])
  if v.get('access')=='deny':print('    host '+mac+' deny')
elif c=='show ip hotspot':
 for mac,v in s['hosts'].items():print('    host:\n        mac: '+mac+'\n        interface:\n            id: '+v['segment']+'\n        access: '+v.get('access','permit'))
elif a[:3]==['ip','hotspot','policy']:s['bindings'][a[3]]=a[4];save()
elif a[:3]==['no','ip','policy']:s['policies'].pop(a[3],None);save()
elif a[:2]==['ip','policy']:
 v=s['policies'].setdefault(a[2],{'description':'','wans':[]})
 if len(a)>3:
  if a[3]=='description':v['description']=a[4]
  elif a[3:5]==['permit','global']:v['wans'].append(a[5])
 save()
elif a[:3]==['ip','hotspot','host']:s['hosts'][a[3]]['policy']=a[5];save()
elif a[:4]==['no','ip','hotspot','host']:s['hosts'][a[4]]['policy']=None;save()
elif c=='system configuration save':
 if s.get('failSave',0):s['failSave']-=1;save();sys.exit(1)
else:raise SystemExit('unsupported fixture command')
'''

class Policies(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fixture = self.root / 'native.json'
        self.mock = self.root / 'ndmc'
        self.mock.write_text(MOCK)
        self.mock.chmod(0o755)
        self.initial = {'wans': ['ISP', 'BackupISP'], 'bindings': {'Home': 'permit', 'Guest': 'permit'},
            'policies': {'Policy7': {'description': 'xkeen', 'wans': ['ISP']},
                         'Policy9': {'description': 'no_vpn', 'wans': ['CustomWAN']},
                         'Policy11': {'description': 'work', 'wans': ['ISP']}},
            'hosts': {
                '00:11:22:33:44:01': {'segment': 'Bridge0', 'policy': 'Policy11'},
                '00:11:22:33:44:02': {'segment': 'Bridge0', 'policy': 'Policy9'},
                '00:11:22:33:44:03': {'segment': 'Guest', 'policy': 'Policy11'},
                '00:11:22:33:44:04': {'segment': 'Bridge0', 'policy': None},
                '00:11:22:33:44:05': {'segment': 'Bridge0', 'policy': 'Policy7'},
                '00:11:22:33:44:06': {'segment': 'Bridge0', 'policy': 'Policy11', 'access': 'deny'}}}
        self.write(self.initial)
        ui = self.root / 'share/xkeen-manager'
        ui.mkdir(parents=True)
        (self.root / 'etc').mkdir()
        (ui / 'xkeen-ui-state.json').write_text(json.dumps({'activeProfileId': 'p', 'profiles': [
            {'id': 'p', 'activeProxyId': 'key', 'proxies': [{'id': 'key', 'config': {'address': 'vpn.example.test'}}]}]}))
        self.env = dict(os.environ, ANTIGOBLIN_POLICY_ROOT=str(self.root), ANTIGOBLIN_POLICY_NDMC=str(self.mock),
            ANTIGOBLIN_POLICY_PARSER=str(REPO / 'ui/xkeen-manager/backend/device-policy-config.awk'), POLICY_FIXTURE=str(self.fixture))

    def tearDown(self): self.tmp.cleanup()
    def write(self, value): self.fixture.write_text(json.dumps(value))
    def read(self): return json.loads(self.fixture.read_text())
    def run_policy(self, action, success=True):
        p = subprocess.run(['sh', str(REPO / 'scripts/xkeen/antigoblin-device-policy.sh'), action], env=self.env, capture_output=True, text=True, timeout=25)
        if success:
            self.assertEqual(p.returncode, 0, p.stderr)
            return json.loads(p.stdout)
        self.assertNotEqual(p.returncode, 0)

    def test_status_and_existing_no_vpn_are_read_only(self):
        self.assertFalse(self.run_policy('status')['enabled'])
        self.run_policy('ensure'); self.run_policy('ensure')
        self.assertEqual(self.read(), self.initial)

    def test_fresh_exception_policy_uses_real_wans_without_enrollment(self):
        s=self.read();del s['policies']['Policy9'];self.write(s)
        info=self.run_policy('ensure');self.assertEqual(info['noVpnPolicy'], 'Policy42')
        self.assertFalse(info['enabled'])
        self.assertEqual(self.read()['bindings'], s['bindings'])
        self.assertEqual(self.read()['policies']['Policy42']['wans'], ['ISP','BackupISP'])
        self.run_policy('ensure');self.assertEqual(len(self.read()['policies']),3)

    def test_enable_repeat_disable_preserves_exceptions_and_guest(self):
        self.assertTrue(self.run_policy('enable')['enabled'])
        s=self.read();self.assertIsNone(s['hosts']['00:11:22:33:44:01']['policy'])
        for n in ['02','03','05','06']:
            mac='00:11:22:33:44:'+n;self.assertEqual(s['hosts'][mac],self.initial['hosts'][mac])
        recovery=(self.root/'etc/antigoblin-device-policy.json').read_bytes()
        self.assertTrue(self.run_policy('ensure')['enabled'], 'installer rerun must retain enabled enrollment')
        self.assertEqual((self.root/'etc/antigoblin-device-policy.json').read_bytes(),recovery)
        self.run_policy('enable')
        self.assertFalse(self.run_policy('disable')['enabled'])
        self.assertEqual(self.read(),self.initial)

    def test_new_manual_no_vpn_choice_survives_disable_and_reenable(self):
        self.run_policy('enable');s=self.read();s['hosts']['00:11:22:33:44:01']['policy']='Policy9';self.write(s)
        self.run_policy('disable');self.run_policy('enable')
        self.assertEqual(self.read()['hosts']['00:11:22:33:44:01']['policy'],'Policy9')

    def test_save_failure_rolls_back_clients_and_segment(self):
        s=self.read();s['failSave']=3;self.write(s)
        self.run_policy('enable',False)
        actual=self.read();actual.pop('failSave',None)
        self.assertEqual(actual,self.initial)
        self.assertFalse((self.root/'etc/antigoblin-device-policy.json').exists())

    def test_half_created_policy_is_removed_on_error(self):
        s=self.read();del s['policies']['Policy9'];s['fail']='description no_vpn';self.write(s)
        self.run_policy('ensure',False)
        self.assertNotIn('Policy42',self.read()['policies'])
        self.assertEqual(self.read()['bindings'],self.initial['bindings'])

    def test_missing_key_does_not_modify_device_policy(self):
        (self.root/'share/xkeen-manager/xkeen-ui-state.json').write_text('{}')
        self.run_policy('enable',False)
        self.assertEqual(self.read(),self.initial)

    def test_external_segment_change_survives_disable(self):
        self.run_policy('enable');s=self.read();s['bindings']['Home']='Policy11';self.write(s)
        self.run_policy('disable');self.assertEqual(self.read()['bindings']['Home'],'Policy11')
        self.run_policy('enable');self.run_policy('disable')
        self.assertEqual(self.read()['bindings']['Home'],'Policy11')

    def test_hotspot_read_failure_does_not_partly_enroll(self):
        s=self.read();s['fail']='show ip hotspot';self.write(s)
        self.run_policy('enable',False);self.assertEqual(self.read(),self.initial)

    def test_duplicate_exception_names_are_not_guessed(self):
        s=self.read();s['policies']['Policy12']={'description':'no_vpn','wans':['OtherWAN']};self.write(s)
        self.run_policy('enable',False);self.assertEqual(self.read(),s)

if __name__=='__main__': unittest.main()
