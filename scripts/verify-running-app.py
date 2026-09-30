#!/usr/bin/env python3
"""Verify that the one running Airdraft instance has the requested build loaded.

Info.plist and the executable launcher can change while an old core/UI library
remains mapped in memory. Compare loaded Mach-O UUIDs, not just version labels.
This is read-only: it never starts, stops, installs or grants permissions to apps.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def output(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, timeout=30)


def running_airdraft():
    instances = []
    for line in output('ps', '-axo', 'pid=,comm=').splitlines():
        columns = line.strip().split(None, 1)
        if len(columns) != 2 or '.app/Contents/MacOS/' not in columns[1]:
            continue
        pid, executable = columns
        app = Path(executable.split('.app/Contents/MacOS/', 1)[0] + '.app')
        try:
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        except (OSError, plistlib.InvalidFileException):
            continue
        if info.get('CFBundleIdentifier') in ('com.lstudlo.app.airdraft', 'com.lstudlo.app.airdraft.debug'):
            instances.append({'pid': int(pid), 'app': str(app.resolve()), 'bundleID': info['CFBundleIdentifier']})
    return instances


def matching_images(binary, app, images, *, debug):
    paths = {binary, binary.resolve()}
    if debug and binary.name == 'AirdraftCore':
        # Xcode's Debug rpath can load its package product directly, rather
        # than the identical embedded copy. It must still match the bundled
        # Mach-O UUID below; never accept a similarly named unknown framework.
        package = app.parent / 'PackageFrameworks/AirdraftCore.framework/AirdraftCore'
        paths.update((package, package.resolve()))
    expected = {str(path) for path in paths}
    home = str(Path.home())
    expected.update(path.replace(home + '/', str(Path.home().parent / '*') + '/', 1)
                    for path in list(expected) if path.startswith(home + '/'))
    return [(uuid.upper(), path) for uuid, path in images if path in expected]


def verify(app, report):
    app = app.resolve(strict=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    instances = running_airdraft()
    report.update(app=str(app), instances=instances, version=info.get('CFBundleShortVersionString'),
                  build=info.get('CFBundleVersion'))
    if len(instances) != 1 or instances[0]['app'] != str(app):
        raise RuntimeError('Expected exactly one Airdraft instance running from the requested app path.')
    pid = instances[0]['pid']
    with tempfile.TemporaryDirectory(prefix='airdraft-running-build-') as directory:
        sample = Path(directory) / 'sample.txt'
        output('sample', str(pid), '1', '1', '-file', str(sample))
        images = re.findall(r'^\s*0x\S+\s*-\s*0x\S+.*?<([0-9A-Fa-f-]{36})>\s+(.+)$',
                            sample.read_text(), re.MULTILINE)
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    binaries = [executable, app / 'Contents/Frameworks/AirdraftCore.framework/AirdraftCore']
    debug_library = executable.with_name(executable.name + '.debug.dylib')
    if debug_library.exists():
        binaries.append(debug_library)
    checks = []
    for binary in binaries:
        suffix = '/' + str(binary.resolve().relative_to(app))
        matches = matching_images(binary, app, images, debug=debug_library.exists())
        loaded = {uuid for uuid, _ in matches}
        disk = set(re.findall(r'UUID: ([0-9A-Fa-f-]{36})', output('xcrun', 'dwarfdump', '--uuid', str(binary))))
        check = {'binary': suffix, 'loaded': sorted(loaded), 'disk': sorted(disk),
                 'loadedPaths': sorted({path for _, path in matches}),
                 'matches': bool(loaded) and loaded <= disk}
        checks.append(check)
    report['binaries'] = checks
    if any(not check['matches'] for check in checks):
        raise RuntimeError('The running process has stale or unverified code. Quit it normally and relaunch the rebuilt app.')
    if running_airdraft() != instances:
        raise RuntimeError('Running instances changed during verification. Repeat against the intended process.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = {'status': 'failed'}
    try:
        verify(args.app, report)
        report['status'] = 'passed'
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report['error'] = str(error)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
