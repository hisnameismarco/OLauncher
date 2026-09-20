# SPDX-License-Identifier: GPL-3.0-only
"""Install a checkout snapshot with the real Omarchy CLI and a private host.

Requires a running Wayland compositor and the documented Omarchy dependencies.
All configuration/state is temporary. Only the copied host is instrumented:
its bar is disabled and a test IPC endpoint exposes the loaded plugin. App
launch requests are captured at the host boundary, without starting real apps.
"""
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
HOST = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy'))

BRIDGE = '''
  IpcHandler {
    target: "releaseReview"
    function inspect(): string {
      var loader = shell.panelLoaders["olauncher"]
      if (!loader || !loader.item) return "{}"
      var p = loader.item
      return JSON.stringify({info:JSON.parse(p.debugInfo()), catalog:p.gridCatalog,
        layout:p.persistentLayout, grid:p.gridApps, hidden:p.hiddenApps,
        usage:p.usage, launches:Util.reviewCommands, hasShell:!!p.shell,
        hasLibrary:!!p.appLibrary, hasHostLibrary:!!shell.appLibrary})
    }
    function invoke(method: string, raw: string): string {
      var p = shell.panelLoaders["olauncher"].item
      var args = JSON.parse(decodeURIComponent(raw))
      p[method].apply(p,args)
      return "ok"
    }
    function key(name: string, control: bool): void {
      shell.panelLoaders["olauncher"].item.handleKey({key:Qt["Key_" + name],
        modifiers:control ? Qt.ControlModifier : 0, accepted:false})
    }
  }
'''


@unittest.skipUnless(shutil.which('qs') and os.environ.get('WAYLAND_DISPLAY'),
                     'Quickshell and Wayland required')
class CleanInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='olauncher-clean-install-')
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.host = self.base / 'host'
        self.config = self.home / '.config'
        self.state = self.base / 'state with spaces'
        self.cache = self.base / 'cache'
        self.data = self.base / 'data'
        self.runtime = self.base / 'runtime'
        for path in [self.home, self.config / 'omarchy', self.state, self.cache,
                     self.data / 'applications', self.host / 'config/omarchy', self.runtime]:
            path.mkdir(parents=True, exist_ok=True)
        self.runtime.chmod(0o700)
        display = Path(os.environ['WAYLAND_DISPLAY'])
        if not display.is_absolute():
            display = Path(os.environ['XDG_RUNTIME_DIR']) / display
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        XDG_STATE_HOME=str(self.state), XDG_CACHE_HOME=str(self.cache),
                        XDG_DATA_HOME=str(self.data), OMARCHY_PATH=str(self.host),
                        XDG_RUNTIME_DIR=str(self.runtime), WAYLAND_DISPLAY=str(display),
                        QT_ACCESSIBILITY='0', NO_AT_BRIDGE='1')
        self.env.pop('QT_QUICK_BACKEND', None)
        self.env.pop('QT_QPA_PLATFORM', None)
        shutil.copytree(HOST / 'shell', self.host / 'shell', symlinks=False)
        # Host CLI helpers remain the installed, documented runtime dependency.
        (self.host / 'bin').symlink_to(HOST / 'bin', target_is_directory=True)
        disabled = []
        for manifest in (self.host / 'shell/plugins').rglob('manifest.json'):
            disabled.append(json.loads(manifest.read_text())['id'])
        config = {'version': 1, 'plugins': [], 'disabledPlugins': disabled,
                  'bar': {'layout': {'left': [], 'center': [], 'right': []}},
                  'idle': {'screensaver': 0, 'lock': 0}}
        for path in [self.config / 'omarchy/shell.json', self.host / 'config/omarchy/shell.json']:
            path.write_text(json.dumps(config))
        shell_path = self.host / 'shell/shell.qml'
        source = shell_path.read_text()
        source = source.replace('active: shell.activeBarId === shell.defaultBarId', 'active: false')
        shell_path.write_text(source[:source.rfind('}')] + BRIDGE + '\n}\n')
        util_path = self.host / 'shell/Commons/Util.qml'
        util = util_path.read_text().replace('QtObject {', 'QtObject {\n  property var reviewCommands: []', 1)
        util = util.replace('function execDetached(command) {', '''function execDetached(command) {
    if (command.indexOf("uwsm-app -- gtk-launch ") === 0) {
      reviewCommands = reviewCommands.concat([command]); return
    }''', 1)
        util_path.write_text(util)
        for name in ['A', 'B', 'C', 'D', 'suffix.desktop']:
            (self.data / f'applications/review-{name}.desktop').write_text(
                f'[Desktop Entry]\nType=Application\nName=Release Review {name}\nExec=/usr/bin/true\nIcon=application-x-executable\n')
        self.snapshot = self.base / 'candidate'
        shutil.copytree(REPO, self.snapshot, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        for args in [['init', '-q'], ['add', '.'], ['-c', 'user.name=Release Test', '-c',
                     'user.email=release-test@example.invalid', 'commit', '-qm', 'Candidate snapshot']]:
            subprocess.run(['git', '-C', str(self.snapshot), *args], check=True, capture_output=True)
        self.plugin = self.config / 'omarchy/plugins/olauncher'
        self.layout = self.state / 'olauncher/apps-layout.json'
        self.usage = self.home / '.local/state/spotlight-usage.json'
        self.log_path = self.base / 'host.log'
        self.log = self.log_path.open('w+')
        self.process = None
        self.addCleanup(self.cleanup)
        self.start()
        self.run_cli('omarchy', 'plugin', 'add', self.snapshot.as_uri(), '--enable', '--yes')
        self.run_cli('omarchy', 'plugin', 'validate', str(self.plugin))
        self.open()

    def run_cli(self, *args):
        result = subprocess.run(args, env=self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def ipc(self, target, method, *args):
        return self.run_cli('omarchy-shell', target, method, *args)

    def wait_for(self, predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.05)
        self.fail('Timed out; runtime log:\n' + self.log_path.read_text())

    def start(self):
        self.process = subprocess.Popen(['dbus-run-session', '--', 'qs', '-p', str(self.host / 'shell'),
                                         '--no-color'], env=self.env, stdout=self.log, stderr=subprocess.STDOUT,
                                        start_new_session=True)
        def ready():
            result = subprocess.run(['omarchy-shell', 'shell', 'ping'], env=self.env,
                                    capture_output=True, text=True, timeout=4)
            return result.returncode == 0 and result.stdout.strip() == 'ok'
        self.wait_for(ready)

    def stop(self):
        if self.process and self.process.poll() is None:
            import signal
            os.killpg(self.process.pid, signal.SIGTERM)
            self.process.wait(timeout=10)
        self.process = None

    def open(self, payload='{}'):
        self.wait_for(lambda: any(p['id'] == 'olauncher' and p['enabled']
                                 for p in json.loads(self.ipc('shell', 'listPlugins'))))
        self.ipc('shell', 'summon', 'olauncher', payload)
        self.wait_for(lambda: self.inspect().get('info', {}).get('opened'))
        self.wait_for(lambda: len(self.inspect()['catalog']) >= 4)

    def inspect(self):
        return json.loads(self.ipc('releaseReview', 'inspect'))

    def invoke(self, method, *args):
        return self.ipc('releaseReview', 'invoke', method, quote(json.dumps(args), safe=''))

    def disk(self):
        return json.loads(self.layout.read_text())

    def saved(self):
        self.wait_for(lambda: self.layout.exists())
        time.sleep(.4)

    def capture(self, name):
        artifact = os.environ.get('OLAUNCHER_REVIEW_ARTIFACTS')
        if artifact and shutil.which('grim'):
            path = Path(artifact) / (name + '.png')
            path.parent.mkdir(parents=True, exist_ok=True)
            time.sleep(.3)
            self.run_cli('grim', str(path))

    def sample_idle(self):
        children = Path(f'/proc/{self.process.pid}/task/{self.process.pid}/children').read_text().split()
        pid = next(pid for pid in children if Path(f'/proc/{pid}/comm').read_text().strip() == 'qs')
        def ticks():
            fields = Path(f'/proc/{pid}/stat').read_text().split()
            return int(fields[13]) + int(fields[14])
        time.sleep(.8)
        start, before = time.monotonic(), ticks()
        time.sleep(2)
        cpu = (ticks() - before) / os.sysconf('SC_CLK_TCK') / (time.monotonic() - start) * 100
        print(f'Isolated host idle CPU: {cpu:.2f}%', flush=True)

    def restart_with(self, raw):
        self.stop()
        self.layout.parent.mkdir(parents=True, exist_ok=True)
        self.layout.write_text(raw)
        self.start()
        self.open('{"filter":"apps"}')

    def test_v1_upgrade_and_idempotent_restart(self):
        order = ['review-C', 'review-A', 'review-B']
        self.restart_with(json.dumps({'version': 1, 'order': order}))
        self.wait_for(lambda: self.disk().get('version') == 2)
        self.assertEqual([i['appId'] for i in self.disk()['items']], order)
        self.assertEqual([a['appId'] for a in self.inspect()['grid'][:3]], order)
        stamp = self.layout.stat().st_mtime_ns
        self.stop(); self.start(); self.open('{"filter":"apps"}')
        self.assertEqual([a['appId'] for a in self.inspect()['grid'][:3]], order)
        time.sleep(.3)
        self.assertEqual(self.layout.stat().st_mtime_ns, stamp)

    def test_malformed_state_remains_usable(self):
        self.restart_with('{broken')
        self.assertGreater(len(self.inspect()['grid']), 4)
        self.assertEqual(self.layout.read_text(), '{broken')
        self.invoke('setQuery', 'Release Review C')
        self.assertTrue(any(r['id'] == 'app:review-C' for r in self.inspect()['info']['results']))
        self.invoke('setQuery', '')
        self.invoke('reorderGrid', 'app:review-C', 0)
        self.saved()
        self.assertEqual(self.disk()['items'][0]['appId'], 'review-C')

    def test_future_schema_all_session_mutations(self):
        raw = '{ "version": 999, "items": [] }\n'
        self.restart_with(raw)
        def unchanged():
            time.sleep(.25)
            self.assertEqual(self.layout.read_text(), raw)
        self.invoke('reorderGrid', 'app:review-C', 0); unchanged()
        self.invoke('folderDrop', 'app:review-A', 'app:review-B'); unchanged()
        folder = next(i for i in self.inspect()['layout'] if i['type'] == 'folder')
        self.invoke('openGridFolder', folder['id'])
        self.invoke('renameGridFolder', 'Session Only'); unchanged()
        self.invoke('changeVisibility', 'hide', 'review-A'); unchanged()
        self.invoke('changeVisibility', 'restore', 'review-A'); unchanged()
        self.invoke('changeVisibility', 'hide', 'review-B'); unchanged()
        self.invoke('changeVisibility', 'restoreAll', ''); unchanged()
        self.invoke('closeGridFolder')
        self.invoke('showGridActions', 'folder:' + folder['id'])
        self.invoke('performAction', 'deleteFolder'); unchanged()
        self.assertFalse(any(i['type'] == 'folder' for i in self.inspect()['layout']))

    def test_clean_install_lifecycle(self):
        self.assertFalse(self.layout.exists())
        self.assertEqual(self.inspect()['info']['filter'], 'all')
        self.capture('normal-launcher')
        self.ipc('shell', 'hide', 'olauncher')
        self.ipc('shell', 'toggle', 'olauncher', '{"filter":"apps"}')
        self.assertTrue(self.inspect()['info']['gridActive'])
        self.capture('apps-grid')
        self.ipc('releaseReview', 'key', 'H', 'true')
        self.assertTrue(self.inspect()['info']['hiddenOpen'])
        self.ipc('releaseReview', 'key', 'Escape', 'false')
        self.assertFalse(self.inspect()['info']['hiddenOpen'])
        first = [a['key'] for a in self.inspect()['grid']]
        self.invoke('close')
        self.open('{"filter":"apps"}')
        self.assertEqual([a['key'] for a in self.inspect()['grid']], first)
        self.assertFalse(self.layout.exists())
        self.invoke('reorderGrid', 'app:review-C', 0)
        self.saved()
        self.assertEqual(self.disk()['items'][0], {'type': 'app', 'appId': 'review-C'})
        self.assertEqual(self.disk()['version'], 2)
        self.assertEqual(self.layout.stat().st_mode & 0o022, 0, 'state must not be group/world writable')
        print(f'Layout file permissions: {self.layout.stat().st_mode & 0o777:o}', flush=True)
        self.sample_idle()
        self.invoke('folderDrop', 'app:review-A', 'app:review-B')
        folder = next(i for i in self.inspect()['layout'] if i['type'] == 'folder')
        self.invoke('openGridFolder', folder['id'])
        self.invoke('renameGridFolder', 'Release Review Folder')
        self.capture('folder')
        self.invoke('changeVisibility', 'hide', 'review-A')
        self.invoke('showHiddenApps')
        self.capture('hidden-apps')
        self.invoke('closeHiddenApps')
        self.saved()
        expected = self.disk()
        self.assertEqual(expected['hidden'], ['review-A'])
        self.assertIn('review-A', next(i for i in expected['items'] if i['type'] == 'folder')['apps'])
        self.stop(); self.start(); self.open('{"filter":"apps"}')
        self.assertEqual(self.disk(), expected)
        self.assertEqual(self.inspect()['layout'], expected['items'])
        self.assertEqual([a['appId'] for a in self.inspect()['hidden']], ['review-A'])
        self.invoke('setQuery', 'Release Review B')
        self.assertTrue(any(r['id'] == 'app:review-B' for r in self.inspect()['info']['results']))
        self.invoke('setQuery', '')
        self.invoke('openGridFolder', folder['id'])
        self.invoke('activateGrid', 'app:review-B')
        self.assertEqual(len(self.inspect()['launches']), 1)
        self.assertIn('review-B.desktop', self.inspect()['launches'][0])
        self.assertEqual(self.inspect()['usage'].get('review-B'), 1)
        self.wait_for(lambda: self.usage.exists())
        self.stop(); self.start(); self.open()
        self.assertEqual(self.inspect()['usage'].get('review-B'), 1)
        self.invoke('cycleQuick', 1)
        self.assertEqual(self.inspect()['info']['quickApps'][0], 'review-B')
        self.assertNotIn('review-A', self.inspect()['info']['quickApps'])
        self.ipc('shell', 'summon', 'olauncher', '{"filter":"apps"}')
        self.assertTrue(self.inspect()['info']['gridActive'])
        self.invoke('changeVisibility', 'restoreAll', '')
        self.saved()
        self.assertEqual(self.disk()['hidden'], [])
        self.invoke('activateGrid', 'app:review-suffix.desktop')
        self.assertIn('review-suffix.desktop.desktop', self.inspect()['launches'][-1],
                      'catalog IDs ending in .desktop still need the filename extension')
        self.run_cli('omarchy', 'plugin', 'remove', 'olauncher', '--yes')
        self.assertFalse(self.plugin.exists())
        self.assertTrue(self.layout.exists(), 'uninstall retains user layout')

    def tearDown(self):
        log = self.log_path.read_text()
        unexpected = [line for line in log.splitlines()
                      if ('WARN scene:' in line or 'ERROR' in line or 'WARN qml:' in line)
                      and 'newer apps-layout schema' not in line
                      and 'invalid apps-layout.json' not in line]
        self.assertEqual(unexpected, [], 'unexpected QML/runtime diagnostics')

    def cleanup(self):
        self.stop()
        self.log.close()
        artifact = os.environ.get('OLAUNCHER_REVIEW_ARTIFACTS')
        if artifact:
            target = Path(artifact)
            target.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.log_path, target / f'{self._testMethodName}.log')
        self.temp.cleanup()


if __name__ == '__main__':
    unittest.main()
