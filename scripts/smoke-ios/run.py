#!/usr/bin/env python3
"""Tap through the five apps on an owned, disposable sample-data simulator."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid

# Scenario imports must not leave bytecode beside the scripts.
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'build/smoke'
APPS = ('Aresium', 'Empire', 'Arestemis', 'Aresus', 'Arestoteles')
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'


class SmokeFailure(Exception):
    pass


def signal_group(pid, signum):
    try:
        os.killpg(pid, signum)
    except ProcessLookupError:
        # The command may have exited just as Ctrl-C or its timeout arrived.
        pass


def command(args, timeout=60, check=True, interrupt_grace=55):
    """Bound commands and reap their entire process group, including on Ctrl-C."""
    WORK.mkdir(parents=True, exist_ok=True)
    # A simulator helper can inherit stdout and keep a pipe open after AXe exits.
    # A file plus wait() bounds the command itself without waiting for pipe EOF.
    with tempfile.TemporaryFile(mode='w+', dir=WORK) as capture:
        process = subprocess.Popen([str(a) for a in args], cwd=ROOT, stdout=capture,
                                   stderr=subprocess.STDOUT, text=True, start_new_session=True)
        try:
            process.wait(timeout=timeout)
        except KeyboardInterrupt as interrupted:
            # Let a self-test child execute its own simulator cleanup.
            signal_group(process.pid, signal.SIGINT)
            try:
                process.wait(timeout=interrupt_grace)
            except subprocess.TimeoutExpired:
                signal_group(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            capture.seek(0)
            try:
                interrupted.output = capture.read()
            except UnicodeError:
                interrupted.output = ''
            raise
        except BaseException:
            signal_group(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
            raise
        capture.seek(0)
        output = capture.read()
    if check and process.returncode:
        raise SmokeFailure(f'{args[0:3]} exited {process.returncode}: {output[-4000:]}')
    return process.returncode, output


class Catalog:
    def __init__(self, app, language):
        self.language = language
        paths = [ROOT / app / app / 'Localizable.xcstrings', ROOT / 'Shared/Shared.xcstrings']
        shared = ROOT / app / f'{app}Shared/{app}Shared.xcstrings'
        if shared.exists():
            paths.append(shared)
        self.tables = [(path, json.loads(path.read_text())['strings']) for path in paths]

    def label(self, english, literal=False, table=None, count=None):
        if literal or (self.language == 'en' and count is None):
            return english
        values = set()
        for path, entries in self.tables:
            if table and path.stem != table:
                continue
            if english in entries:
                localized = entries[english].get('localizations', {}).get(self.language, {})
                if count is not None:
                    plural = localized.get('variations', {}).get('plural', {})
                    localized = plural.get('one' if count == 1 else 'other', localized)
                value = localized.get('stringUnit', {}).get('value')
                if value is not None:
                    if count is not None:
                        value = value.replace('%lld', str(count))
                    values.add(value)
        if not values:
            raise SmokeFailure(f'No {"German" if self.language == "de" else "English"} catalog entry for English label {english!r}; use an identifier or a catalog key')
        if len(values) != 1:
            raise SmokeFailure(f'Ambiguous German catalog entries for {english!r}: {sorted(values)}')
        return values.pop()


def elements(tree):
    if isinstance(tree, list):
        for child in tree:
            yield from elements(child)
    elif isinstance(tree, dict):
        if 'AXLabel' in tree or 'AXUniqueId' in tree:
            yield tree
        for value in tree.values():
            if isinstance(value, (list, dict)):
                yield from elements(value)


def visible_elements(tree):
    """Ignore scroll content whose accessibility frames lie outside the screen."""
    nodes = list(elements(tree))
    application = next((node for node in nodes if node.get('type') == 'Application'), {})
    screen = application.get('frame', dict(x=0, y=0, width=402, height=874))
    # AXe sometimes gives the application itself a zero frame on a sheet, while
    # its children have valid screen coordinates. The owned iPhone 17 is 402×874.
    if screen['width'] <= 0 or screen['height'] <= 0:
        screen = dict(x=0, y=0, width=402, height=874)
    for node in nodes:
        if node.get('type') == 'Application':
            yield node                 # process identity need not have a visible frame
            continue
        frame = node.get('frame')
        if frame and (frame['width'] <= 0 or frame['height'] <= 0 or
                      frame['x'] + frame['width'] <= screen['x'] or
                      frame['y'] + frame['height'] <= screen['y'] or
                      frame['x'] >= screen['x'] + screen['width'] or
                      frame['y'] >= screen['y'] + screen['height']):
            continue
        yield node


class Runner:
    def __init__(self, udid, app, bundle, folder, language):
        self.udid, self.app, self.bundle, self.folder = udid, app, bundle, folder
        self.catalog = Catalog(app, language)
        self.language = language
        self.steps = 0
        self.current = 'starting'
        self.tree = []
        self.pending = None
        self.pid = None
        self.last_describe_error = None
        folder.mkdir(parents=True, exist_ok=True)

    def step(self, description):
        self.steps += 1
        self.current = f'{self.steps}: {description}'
        with (self.folder / 'steps.jsonl').open('a') as log:
            log.write(json.dumps({'step': self.steps, 'action': description, 'time': time.time()}) + '\n')

    def describe(self, timeout=35):
        _, output = command(['axe', 'describe-ui', '--udid', self.udid], timeout=timeout)
        tree = json.loads(output)
        if not any(node.get('type') == 'Application' for node in elements(tree)):
            raise SmokeFailure('AXe returned no application tree; retaining the last valid snapshot')
        self.tree = tree
        self.last_describe_error = None
        return self.tree

    def selector(self, label=None, *, id=None, literal=False, contains=False, type=None, value=None, table=None,
                 child_id=None, enabled=None, in_value=False, ignore_case=False, count=None, pid=None):
        if (label is None) == (id is None):
            raise SmokeFailure('Specify exactly one of label or id')
        return dict(label=self.catalog.label(label, literal, table, count) if label is not None else None,
                    id=id, contains=contains, type=type, value=value, child_id=child_id, enabled=enabled,
                    in_value=in_value, ignore_case=ignore_case, pid=pid)

    @staticmethod
    def matches(tree, selector):
        found = []
        for element in visible_elements(tree):
            key = 'AXUniqueId' if selector['id'] is not None else ('AXValue' if selector.get('in_value') else 'AXLabel')
            wanted = selector['id'] if selector['id'] is not None else selector['label']
            actual = str(element.get(key) or '')
            if selector.get('pid') is not None:
                wanted, actual = str(selector['pid']), str(element.get('pid'))
            if selector.get('ignore_case'):
                wanted, actual = wanted.casefold(), actual.casefold()
            if (wanted in actual if selector['contains'] else wanted == actual):
                if selector['type'] and element.get('type') != selector['type']:
                    continue
                if selector['value'] is not None and selector['value'] not in str(element.get('AXValue') or ''):
                    continue
                if selector.get('child_id') and not any(
                        child.get('AXUniqueId') == selector['child_id'] for child in elements(element.get('children', []))):
                    continue
                if selector.get('enabled') is not None and element.get('enabled') != selector['enabled']:
                    continue
                found.append(element)
        return found

    def check(self, selector, present, timeout):
        deadline = time.monotonic() + timeout
        stable = None
        stable_since = None
        # A successful AXe tap alone never clears pending. The assertion must have
        # been false before the tap and become true afterwards.
        if self.pending:
            action, before = self.pending
            if bool(self.matches(before, selector)) == present:
                raise SmokeFailure(f'Assertion already true before {action}; choose an observable change: {selector}')
        while time.monotonic() < deadline:
            try:
                tree = self.describe(timeout=min(35, max(.1, deadline - time.monotonic())))
                application = next((node for node in elements(tree) if node.get('type') == 'Application'), {})
                wrong_pid = self.pid is not None and application.get('pid') != self.pid
                if wrong_pid or (self.pid is None and application.get('AXLabel') not in (None, self.app)):
                    self.last_describe_error = f'Foreground app is {application.get("AXLabel")!r}, expected {self.app!r}'
                    time.sleep(.35)
                    continue
                if bool(self.matches(tree, selector)) == present:
                    matches = self.matches(tree, selector)
                    signature = json.dumps([(e.get('AXLabel'), e.get('AXValue'), e.get('frame')) for e in matches],
                                           sort_keys=True)
                    if signature != stable:
                        stable, stable_since = signature, time.monotonic()
                    elif time.monotonic() - stable_since >= .6:
                        self.pending = None
                        (self.folder / 'last-ui.json').write_text(json.dumps(tree, indent=2, ensure_ascii=False))
                        return matches
                else:
                    stable, stable_since = None, None
            except (SmokeFailure, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
                # The first call after boot often times out. Retry within the same
                # bounded wait; later transient AXe failures get the same treatment.
                self.last_describe_error = str(error)
            time.sleep(min(.35, max(0, deadline - time.monotonic())))
        raise SmokeFailure(f'Timed out after {timeout}s waiting for {selector}, present={present}'
                           + (f'; last AXe error: {self.last_describe_error}' if self.last_describe_error else ''))

    def wait_for(self, label=None, *, timeout=60, present=True, **kwargs):
        self.step(f'wait_for {label or kwargs.get("id")!r}, present={present}, {kwargs}')
        return self.check(self.selector(label, **kwargs), present, timeout)

    def expect(self, label=None, *, present=True, timeout=40, **kwargs):
        self.step(f'expect {label or kwargs.get("id")!r}, present={present}, {kwargs}')
        return self.check(self.selector(label, **kwargs), present, timeout)

    def tap(self, label=None, **kwargs):
        if self.pending:
            raise SmokeFailure(f'Unverified action before next tap: {self.pending[0]}')
        selector = self.selector(label, **kwargs)
        self.step(f'tap {selector}')
        self.check(selector, True, 60)
        before = self.tree
        matches = self.matches(before, selector)
        if len(matches) != 1:
            raise SmokeFailure(f'Tap target is ambiguous ({len(matches)} matches): {selector}')
        target = matches[0]
        # The selector was resolved in the fresh tree above. Reuse its frame so
        # AXe does not start a second accessibility session just to resolve it again.
        frame = target['frame']
        args = ['axe', 'tap', '-x', frame['x'] + frame['width'] / 2,
                '-y', frame['y'] + frame['height'] / 2,
                '--tap-style', 'physical', '--udid', self.udid]
        command(args, timeout=90)
        self.pending = (self.current, before)

    def type(self, text):
        self.step(f'type {text!r}')
        command(['axe', 'type', text, '--udid', self.udid], timeout=90)

    def swipe(self, start=(200, 690), end=(200, 300)):
        if self.pending:
            raise SmokeFailure('Verify the tap before swiping')
        self.step(f'swipe {start} -> {end}')
        before = self.describe()
        command(['axe', 'swipe', '--start-x', start[0], '--start-y', start[1],
                 '--end-x', end[0], '--end-y', end[1], '--duration', '.4', '--udid', self.udid])
        self.pending = (self.current, before)

    def screenshot(self, name):
        self.step(f'screenshot {name}')
        path = self.folder / f'{name}.png'
        command(['xcrun', 'simctl', 'io', self.udid, 'screenshot', str(path)])
        return path

    def relaunch(self, args=()):
        if self.pending:
            raise SmokeFailure('Verify the tap before relaunching')
        self.step(f'relaunch {list(args)}')
        command(['xcrun', 'simctl', 'terminate', self.udid, self.bundle], check=False)
        _, output = command(['xcrun', 'simctl', 'launch', self.udid, self.bundle, '-sampleData', *args,
                             '-AppleLanguages', f'({self.language})', '-AppleLocale',
                             'de_DE' if self.language == 'de' else 'en_GB'])
        launched = re.search(rf'^{re.escape(self.bundle)}:\s*(\d+)\s*$', output, re.MULTILINE)
        if not launched:
            raise SmokeFailure(f'simctl launch did not return the app PID: {output}')
        self.pid = int(launched.group(1))
        # Starting AXe's remote session on a fresh device can consume more than
        # one command timeout. Keep that bounded startup retry separate from the
        # scenario's screen assertions and their normal deadlines.
        self.wait_for(self.app, literal=True, type='Application', pid=self.pid, timeout=120)

    def finish(self):
        if self.pending:
            raise SmokeFailure(f'Unverified final action: {self.pending[0]}')

    def visible(self):
        return list(visible_elements(self.tree))

    def require(self, condition, description):
        self.step(f'expect {description}')
        if self.pending:
            raise SmokeFailure('Verify the UI action before comparing observed data')
        if not condition:
            raise SmokeFailure(description)

    def failure(self, error):
        failed_step = self.current
        capture_errors = []
        for attempt in range(2):
            try:
                self.describe(timeout=35)
                break
            except Exception as capture_error:
                if attempt == 1:
                    capture_errors.append(str(capture_error))
                else:
                    time.sleep(.35)
        dump = self.folder / 'failure-ui.json'
        dump.write_text(json.dumps(self.tree, indent=2, ensure_ascii=False))
        shot = self.folder / 'failure.png'
        try:
            command(['xcrun', 'simctl', 'io', self.udid, 'screenshot', str(shot)], timeout=20)
        except Exception as capture_error:
            capture_errors.append(str(capture_error))
        labels = [e.get('AXLabel') for e in visible_elements(self.tree) if e.get('AXLabel')]
        report = dict(app=self.app, pid=self.pid, step=failed_step, error=str(error), visible_labels=labels,
                      screenshot=str(shot), describe_ui=str(dump), capture_errors=capture_errors)
        (self.folder / 'failure.json').write_text(json.dumps(report, indent=2, ensure_ascii=False))
        print(f'FAIL {self.app} step {failed_step}\n  {error}\n  Visible labels: {json.dumps(labels, ensure_ascii=False)}'
              f'\n  Screenshot: {shot}\n  describe-ui JSON: {dump}', flush=True)
        if capture_errors:
            print(f'  Capture errors (UI JSON may be the last successful snapshot): {capture_errors}', flush=True)
        return report


def scenario(app):
    path = Path(__file__).parent / 'scenarios' / f'{app.lower()}.py'
    spec = importlib.util.spec_from_file_location(app.lower(), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def cleanup(udid, simulator):
    """Always attempt delete, even when shutdown itself fails or times out."""
    target = udid or simulator
    try:
        command(['xcrun', 'simctl', 'shutdown', target], timeout=45, check=False)
    except Exception as error:
        print(f'Owned simulator shutdown failed; attempting delete: {error}', flush=True)
    try:
        code, output = command(['xcrun', 'simctl', 'delete', target], timeout=45, check=False)
        if code and udid:
            raise SmokeFailure(output)
    except Exception as error:
        print(f'FAIL deleting owned simulator {target}: {error}', flush=True)
        return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apps', nargs='*', choices=None)
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--language', choices=('en', 'de'), default='en')
    parser.add_argument('--appearance', choices=('light', 'dark'), default='light')
    parser.add_argument('--app-path', action='append', default=[], metavar='App=path.app')
    parser.add_argument('--keep', action='store_true', help='keep this run’s owned simulator for inspection')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--inject-failure', action='store_true', help=argparse.SUPPRESS)
    options = parser.parse_args()
    names = {app.lower(): app for app in APPS}
    if options.all and options.apps:
        parser.error('--all and named apps are mutually exclusive')
    try:
        apps = [names[name.lower()] for name in options.apps] if options.apps else list(APPS)
        supplied = {}
        for setting in options.app_path:
            name, path = setting.split('=', 1)
            supplied[names[name.lower()]] = Path(path).expanduser().resolve()
    except (KeyError, ValueError):
        parser.error('Use app names ' + ', '.join(APPS) + ' and --app-path App=path.app')
    if len(set(apps)) != len(apps):
        parser.error('Each app may be named only once')
    if options.self_test:
        return self_test(options)
    run_id = time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    folder = WORK / run_id
    folder.mkdir(parents=True)
    simulator = 'smoke-' + uuid.uuid4().hex
    udid = None
    runner = None
    started = time.monotonic()
    summaries = []
    status = 0
    print(f'Run: {folder}\nSimulator: {simulator}', flush=True)
    try:
        _, output = command(['xcrun', 'simctl', 'create', simulator, 'iPhone 17', RUNTIME])
        udid = output.strip()
        command(['xcrun', 'simctl', 'boot', udid])
        command(['xcrun', 'simctl', 'bootstatus', udid, '-b'], timeout=180)
        command(['xcrun', 'simctl', 'ui', udid, 'appearance', options.appearance])
        for app in apps:
            runner = Runner(udid, app, '', folder / app, options.language)
            app_started = time.monotonic()
            runner.step('build/install')
            if app in supplied:
                app_path = supplied[app]
            else:
                args = ['xcodebuild', 'build', '-project', f'{app}/{app}.xcodeproj', '-scheme', app,
                        '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={udid}',
                        '-derivedDataPath', WORK / 'DerivedData', 'CODE_SIGNING_ALLOWED=NO']
                print(f'Building {app} (log: {runner.folder / "build.log"})', flush=True)
                (runner.folder / 'build-command.json').write_text(json.dumps([str(a) for a in args]))
                code, output = command(args, timeout=900, check=False)
                (runner.folder / 'build.log').write_text(output)
                if code:
                    raise SmokeFailure(f'Build exited {code}; see {runner.folder / "build.log"}: {output[-1500:]}')
                app_path = WORK / 'DerivedData/Build/Products/Debug-iphonesimulator' / f'{app}.app'
            with (app_path / 'Info.plist').open('rb') as file:
                runner.bundle = plistlib.load(file)['CFBundleIdentifier']
            command(['xcrun', 'simctl', 'install', udid, app_path])
            module = scenario(app)
            runner.relaunch(getattr(module, 'ARGS', ()))
            module.run(runner)
            runner.finish()
            if options.inject_failure:
                runner.wait_for(id='smoke-deliberately-missing', timeout=10)
            line = f'PASS {app}: {runner.steps} steps, {time.monotonic() - app_started:.1f}s'
            print(line, flush=True)
            summaries.append(line)
            command(['xcrun', 'simctl', 'terminate', udid, runner.bundle], check=False)
            runner = None
    except KeyboardInterrupt:
        status = 130
        if runner:
            runner.failure('Interrupted (Ctrl-C / SIGTERM)')
        else:
            print('FAIL interrupted', flush=True)
    except Exception as error:
        status = 1
        if runner:
            runner.failure(error)
        else:
            print(f'FAIL setup: {error}', flush=True)
    finally:
        if not options.keep:
            # Name is unique and owned even if create was interrupted before its
            # output was assigned. Never operate on a shared/booted device alias.
            if not cleanup(udid, simulator):
                status = status or 1
        else:
            print(f'Kept owned simulator: {simulator} ({udid})', flush=True)
    summary = (f'SUMMARY: {len(summaries)}/{len(apps)} apps passed; '
               f'{options.language}/{options.appearance}; {time.monotonic() - started:.1f}s; exit {status}')
    print(summary, flush=True)
    (folder / 'summary.json').write_text(json.dumps(dict(lines=summaries, summary=summary, exit=status,
                                                       simulator=simulator, udid=udid), indent=2))
    return status


def self_test(options):
    """Exercise the real CLI and its nonzero failure path, not a mocked assertion."""
    args = [sys.executable, str(Path(__file__).resolve()), 'Empire', '--inject-failure',
            '--language', options.language, '--appearance', options.appearance]
    for path in options.app_path:
        args += ['--app-path', path]
    try:
        # The child owns a simulator. Its bounded failure capture and cleanup can
        # outlast an ordinary tool's interrupt grace; let that finally finish.
        code, output = command(args, timeout=1200, check=False, interrupt_grace=300)
    except KeyboardInterrupt as interrupted:
        print(getattr(interrupted, 'output', ''), end='', flush=True)
        print('SELF-TEST interrupted', flush=True)
        return 130
    print(output, end='', flush=True)
    run_line = next((line[5:] for line in output.splitlines() if line.startswith('Run: ')), None)
    if not run_line:
        print('SELF-TEST FAIL: child did not report its artifacts')
        return 1
    folder = Path(run_line)
    report_path = folder / 'Empire/failure.json'
    if report_path.exists():
        report = json.loads(report_path.read_text())
        captured = json.loads(Path(report['describe_ui']).read_text())
        captured_nodes = list(elements(captured))
        missing = not any(node.get('AXUniqueId') == 'smoke-deliberately-missing' for node in captured_nodes)
        empire = report.get('pid') is not None and any(
                     node.get('type') == 'Application' and node.get('pid') == report['pid']
                     for node in captured_nodes)
        if (code == 1 and 'smoke-deliberately-missing' in report['error'] and
                'Timed out' in report['error'] and report['visible_labels'] and
                Path(report['screenshot']).is_file() and not report['capture_errors'] and
                missing and empire):
            _, devices = command(['xcrun', 'simctl', 'list', 'devices', '--json'])
            name = json.loads((folder / 'summary.json').read_text())['simulator']
            if name not in devices:
                print('SELF-TEST PASS: deliberate expectation failed with step, visible labels, screenshot and UI JSON; simulator deleted')
                return 0
    print(f'SELF-TEST FAIL: expected deliberate assertion report and nonzero exit; child exit {code}')
    return 1


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    sys.exit(main())
