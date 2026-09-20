# SPDX-License-Identifier: GPL-3.0-only
"""Exercise the real Quickshell FileView store in isolated XDG state directories."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from urllib.parse import quote

REPO = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which('qs'), 'Quickshell required')
class LayoutStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='olauncher-layout-')
        self.base = Path(self.temp.name)
        self.config = self.base / 'config'
        self.config.mkdir()
        self.home = self.base / 'home'
        self.home.mkdir()
        self.state = self.base / 'state with spaces'
        self.path = self.state / 'olauncher/apps-layout.json'
        self.process = None
        self.log = (self.base / 'runtime.log').open('w+')
        (self.config / 'shell.qml').write_text('''
import QtQuick
import Quickshell
import Quickshell.Io
import "%s/model"
import "%s/logic/AppLayout.js" as Layout
ShellRoot {
  AppLayoutStore { id: store }
  IpcHandler {
    target: "test"
    function info(): string { return JSON.stringify({hidden:store.hidden,ready:store.ready,order:store.order,items:store.items,protected:store.protectedFile,dirty:store.dirty,writing:store.writing,path:store.path,error:store.lastError}) }
    function commit(raw: string, id: string, target: int): bool { return store.commit(JSON.parse(decodeURIComponent(raw)),id,target) }
    function project(raw: string): string { return JSON.stringify(Layout.allAppIds(Layout.reconcileLayout(store.items,JSON.parse(decodeURIComponent(raw))))) }
    function mutate(operation: string, args: string): bool { return store.mutate(store.items,operation,JSON.parse(decodeURIComponent(args))) }
    function visibility(operation: string, id: string): bool { return store.setVisibility(operation,id,store.items) }
    function flush(): void { store.flush() }
  }
}
''' % (REPO.as_uri(), REPO.as_uri()))

    def start(self, use_xdg=True):
        env = dict(os.environ, HOME=str(self.home), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        if use_xdg:
            env['XDG_STATE_HOME'] = str(self.state)
        else:
            env.pop('XDG_STATE_HOME', None)
        self.process = subprocess.Popen(['qs','-p',str(self.config),'--no-color'],env=env,stdout=self.log,stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                self.fail(self.logs())
            try:
                info = self.info()
                if info['ready']:
                    return info
            except (ValueError, subprocess.SubprocessError):
                pass
            time.sleep(.04)
        self.fail('Store startup timed out: '+self.logs())

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=5)
        self.process = None

    def call(self, method, *args):
        if method in ('commit','project'):
            args = (quote(args[0], safe=''), *args[1:])
        if method == 'mutate':
            args = (args[0], quote(args[1], safe=''))
        return subprocess.check_output(['qs','ipc','--any-display','-p',str(self.config),'call','test',method,*map(str,args)],text=True,timeout=3).strip()

    def info(self):
        return json.loads(self.call('info'))

    def logs(self):
        self.log.flush()
        return (self.base / 'runtime.log').read_text()

    def saved(self):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            info = self.info()
            if not info['dirty'] and not info['writing']:
                return info
            time.sleep(.04)
        self.fail('Save timed out: '+self.logs())

    def disk_order(self):
        return [i['appId'] for i in json.loads(self.path.read_text())['items']]

    def seed(self, text):
        self.path.parent.mkdir(parents=True,exist_ok=True)
        self.path.write_text(text)

    def test_xdg_atomic_save_and_restart(self):
        info = self.start()
        self.assertEqual(info['path'],str(self.path))
        self.assertFalse(self.path.exists(), 'opening must not initialize state')
        self.assertEqual(self.call('commit','["A","B","C"]','C',0),'true')
        self.saved()
        self.assertEqual(json.loads(self.path.read_text()), {'version':2,'items':[{'type':'app','appId':id} for id in ['C','A','B']],'hidden':[]})
        self.assertFalse((self.home / '.local/state/olauncher/apps-layout.json').exists())
        old_inode = self.path.stat().st_ino
        self.call('commit','["C","A","B"]','C',2)
        self.saved()
        self.assertNotEqual(self.path.stat().st_ino,old_inode,'atomic replacement uses a new inode')
        self.assertEqual(list(self.path.parent.iterdir()),[self.path],'no abandoned temporary file')
        self.stop()
        self.assertEqual(self.start()['order'],['A','B','C'])

    def test_noop_does_not_schedule_save(self):
        self.start()
        self.assertEqual(self.call('commit','["A","B"]','A',0),'false')
        self.assertEqual(self.call('commit','["A","B"]','missing',1),'false')
        self.assertFalse(self.info()['dirty'])
        self.call('flush')
        time.sleep(.3)
        self.assertFalse(self.path.exists())

    def test_unreadable_file_is_protected(self):
        self.path.mkdir(parents=True)
        self.start()
        self.assertTrue(self.info()['protected'])
        self.call('commit','["A","B"]','B',0)
        self.call('flush')
        time.sleep(.3)
        self.assertTrue(self.path.is_dir())
        self.assertFalse(self.info()['dirty'])

    def test_future_schema_protected_during_reorder(self):
        raw = '{"version":999,"order":["example"]}\n'
        self.seed(raw)
        info = self.start()
        self.assertTrue(info['protected'])
        self.assertEqual(info['order'],[])
        self.call('commit','["A","B"]','B',0)
        self.call('flush')
        time.sleep(.3)
        self.assertEqual(self.info()['order'],['B','A'],'session-only reordering remains usable')
        self.assertFalse(self.info()['dirty'])
        self.assertEqual(self.path.read_text(),raw)
        self.assertEqual(self.logs().count('newer apps-layout schema'),1)

    def test_catalog_changes_never_write(self):
        raw = json.dumps({'version':2,'items':[{'type':'app','appId':id} for id in ['C','A','B']],'hidden':[]})+'\n'
        self.seed(raw)
        self.start()
        stat = self.path.stat()
        for available, expected in [('[]',[]),('["A","C"]',['C','A']),('["A","B","C","D"]',['C','A','B','D'])]:
            self.assertEqual(json.loads(self.call('project',available)),expected)
            self.assertEqual(self.info()['order'],['C','A','B'])
        self.call('flush')
        time.sleep(.3)
        self.assertEqual(self.path.read_text(),raw)
        self.assertEqual(self.path.stat().st_mtime_ns,stat.st_mtime_ns)

    def test_malformed_recovery_only_after_reorder(self):
        self.seed('{broken')
        self.start()
        self.assertEqual(self.info()['order'],[])
        self.assertEqual(self.path.read_text(),'{broken')
        self.assertIn('invalid apps-layout.json',self.logs())
        self.call('commit','["A","B"]','B',0)
        self.saved()
        self.assertEqual(self.disk_order(),['B','A'])

    def test_default_home_path_and_coalesced_commits(self):
        info = self.start(use_xdg=False)
        path = self.home / '.local/state/olauncher/apps-layout.json'
        self.assertEqual(info['path'],str(path))
        self.call('commit','["A","B","C"]','C',0)
        self.call('commit','["C","A","B"]','A',0)
        self.saved()
        self.assertEqual([i['appId'] for i in json.loads(path.read_text())['items']],['A','C','B'])

    def test_v1_migrates_full_order_without_catalog(self):
        self.seed('{"version":1,"order":["stale","C","A","C","B"]}')
        self.start()
        self.saved()
        self.assertEqual(json.loads(self.path.read_text())['version'],2)
        self.assertEqual(self.disk_order(),['stale','C','A','B'])
        stamp=self.path.stat().st_mtime_ns
        self.stop()
        self.assertEqual(self.start()['order'],['stale','C','A','B'])
        time.sleep(.3)
        self.assertEqual(self.path.stat().st_mtime_ns,stamp,'v2 restart does not migrate again')

    def test_folder_lifecycle_and_restart(self):
        self.seed('{"version":1,"order":["A","B","C","D"]}')
        self.start(); self.saved()
        self.call('mutate','create',json.dumps(['A','B','folder-test']))
        self.call('mutate','add',json.dumps(['C','folder-test']))
        self.call('mutate','rename',json.dumps(['folder-test','Development']))
        self.call('mutate','inside',json.dumps(['folder-test','C',0]))
        self.saved()
        expected=[{'type':'folder','id':'folder-test','name':'Development','apps':['C','B','A']},{'type':'app','appId':'D'}]
        self.assertEqual(json.loads(self.path.read_text())['items'],expected)
        self.stop(); self.assertEqual(self.start()['items'],expected)
        self.call('mutate','delete',json.dumps(['folder-test']))
        self.saved()
        self.assertEqual(self.disk_order(),['C','B','A','D'])
        self.stop(); self.assertEqual(self.start()['order'],['C','B','A','D'])

    def test_future_protects_folder_mutations(self):
        raw='{ "version":999, "items":[{"unknown":true}] }'
        self.seed(raw); self.start()
        self.call('commit','["A","B","C"]','C',0)
        for operation,args in [('create',['A','B','f']),('add',['C','f']),('rename',['f','Work']),('inside',['f','A',0]),('remove',['f','C']),('delete',['f'])]:
            self.call('mutate',operation,json.dumps(args))
        self.call('flush'); time.sleep(.3)
        self.assertEqual(self.path.read_text(),raw)
        self.assertFalse(self.info()['dirty'])
        self.assertEqual(self.info()['order'],['A','B','C'])

    def test_old_v2_and_hidden_restart(self):
        items=[{'type':'app','appId':i} for i in ['A','B','C']]
        self.seed(json.dumps({'version':2,'items':items}))
        self.assertEqual(self.start()['hidden'],[])
        inode=self.path.stat().st_ino
        self.call('visibility','hide','B'); self.saved()
        self.assertNotEqual(self.path.stat().st_ino,inode)
        self.stop(); info=self.start()
        self.assertEqual(info['hidden'],['B'])
        self.assertEqual(info['items'],items)
        self.call('visibility','restore','B'); self.saved()
        self.stop(); info=self.start()
        self.assertEqual(info['hidden'],[])
        self.assertEqual(info['items'],items)

    def test_hidden_folder_membership_and_restore_all(self):
        items=[{'type':'folder','id':'f','name':'Work','apps':['A','B','C']}]
        self.seed(json.dumps({'version':2,'items':items}))
        self.start()
        for app in ['B','A','C','stale']:
            self.call('visibility','hide',app)
        self.saved(); self.stop()
        info=self.start()
        self.assertEqual(info['items'],items)
        self.assertEqual(info['hidden'],['B','A','C','stale'])
        self.call('project','[]')
        self.assertEqual(self.info()['hidden'],['B','A','C','stale'])
        self.call('visibility','restore','B'); self.saved()
        self.stop(); info=self.start()
        self.assertEqual(info['items'],items)
        self.assertEqual(info['hidden'],['A','C','stale'])
        self.call('visibility','restoreAll',''); self.saved()
        self.stop(); info=self.start()
        self.assertEqual(info['hidden'],[])
        self.assertEqual(info['items'],items)

    def test_future_protects_hide_and_restore(self):
        raw='{ "version":999, "hidden":["A"], "items":[] }\n'
        self.seed(raw); self.start()
        for operation,app in [('hide','A'),('restore','A'),('hide','B'),('restoreAll','')]:
            self.call('visibility',operation,app)
            self.call('flush'); time.sleep(.25)
            self.assertEqual(self.path.read_text(),raw)
            self.assertFalse(self.info()['dirty'])
        self.assertEqual(self.logs().count('newer apps-layout schema'),1)

    def test_malformed_hidden_normalizes_without_rewriting_on_load(self):
        raw=json.dumps({'version':2,'items':[], 'hidden':[12,None,'stale','stale']})
        self.seed(raw)
        self.assertEqual(self.start()['hidden'],['stale'])
        self.assertEqual(self.path.read_text(),raw)
        self.call('visibility','hide','A'); self.saved()
        self.stop()
        self.assertEqual(self.start()['hidden'],['stale','A'])

    def test_anchored_reorders_and_folder_deletion_keep_hidden(self):
        items=[{'type':'app','appId':i} for i in ['A','B','C','D']]
        items.append({'type':'folder','id':'f','name':'Work','apps':['X','Y','Z']})
        self.seed(json.dumps({'version':2,'items':items,'hidden':['B','Y']}))
        self.start()
        self.call('mutate','moveVisible',json.dumps(['app:D',0,['app:A','app:C','app:D','folder:f']]))
        self.call('mutate','insideVisible',json.dumps(['f','Z',0,['X','Z']]))
        self.saved(); self.stop()
        info=self.start()
        self.assertEqual(info['hidden'],['B','Y'])
        self.assertEqual(info['order'],['D','A','B','C','Z','X','Y'])
        self.call('mutate','delete',json.dumps(['f'])); self.saved(); self.stop()
        info=self.start()
        self.assertEqual(info['hidden'],['B','Y'])
        self.assertEqual(info['order'],['D','A','B','C','Z','X','Y'])
        self.assertTrue(all(i['type']=='app' for i in info['items']))

    def tearDown(self):
        self.stop()
        self.log.close()
        self.temp.cleanup()

if __name__ == '__main__':
    unittest.main()
