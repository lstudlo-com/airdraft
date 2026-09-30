#!/usr/bin/env python3
"""Require actual native and web editor delivery from the exact Debug build."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib


def app_hashes(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    binaries = [executable, app / 'Contents/Frameworks/AirdraftCore.framework/AirdraftCore',
                executable.with_name(executable.name + '.debug.dylib')]
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in binaries}


def validate(reports, hashes):
    required = {(app, method) for app in ('com.apple.TextEdit', 'com.google.Chrome')
                for method in ('auto', 'paste')}
    seen, tokens = set(), set()
    if not reports:
        raise ValueError('Live insertion evidence is missing; prepare disposable TextEdit and Chrome fields.')
    for report in reports:
        if not (report.get('action') == 'insert' and report.get('status') == 'passed'
                and report.get('actualTextMatches') is True and type(report.get('deliveryCallbacks')) is int
                and report['deliveryCallbacks'] == 1
                and report.get('reportedMethod') == 'paste' and report.get('notice') == ''
                and report.get('binarySHA256') == hashes):
            raise ValueError('Failed, incomplete or stale live insertion evidence; rerun against this Debug build.')
        token = report.get('fixtureToken')
        if not token or token in tokens:
            raise ValueError('Every live insertion must use a fresh disposable fixture token.')
        tokens.add(token)
        seen.add((report.get('targetBundle'), report.get('requestedMethod')))
    if required - seen:
        raise ValueError(f'Missing native/web insertion cases: {sorted(required - seen)}')
    return {'status': 'passed', 'cases': len(reports), 'binarySHA256': hashes,
            'verifiedTargets': [list(case) for case in sorted(seen)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--reports', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    try:
        reports = [json.loads(path.read_text()) for path in sorted(args.reports.glob('*/result.json'))]
        result = validate(reports, app_hashes(args.app))
    except (ValueError, OSError, KeyError) as error:
        result = {'status': 'failed', 'error': str(error)}
    args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
