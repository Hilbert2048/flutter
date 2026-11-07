#!/usr/bin/env python3
"""Verify registered artifacts and, optionally, an App's embedded engine UUID."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from config import Selection, ToolchainError


def uuids(binary):
    result = subprocess.run(['xcrun', 'dwarfdump', '--uuid', str(binary)],
                            capture_output=True, text=True, check=True)
    values = dict((arch, value.upper()) for value, arch in
                  re.findall(r'UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)', result.stdout))
    if not values:
        raise ToolchainError(f'No Mach-O UUID found: {binary}')
    return values


def app_identity(app, required_bundle=None):
    bundle = plistlib.loads((app / 'Info.plist').read_bytes()).get('CFBundleIdentifier')
    if not bundle or (required_bundle and bundle != required_bundle):
        raise ToolchainError(f'App bundle mismatch: {bundle}; expected {required_bundle}')
    seen = {bundle: app}
    for plist in (app / 'Frameworks').glob('*.framework/Info.plist'):
        identifier = plistlib.loads(plist.read_bytes()).get('CFBundleIdentifier')
        if not identifier or identifier in seen:
            raise ToolchainError(f'Missing or duplicate framework bundle ID: {plist}; {identifier}')
        seen[identifier] = plist.parent
    return bundle


def kernel_sdk_hash(app, expected=None):
    path = app / 'Frameworks/App.framework/flutter_assets/kernel_blob.bin'
    if not path.exists():
        return None  # AOT packages do not contain a JIT application kernel.
    with path.open('rb') as stream:
        header = stream.read(18)
    if len(header) != 18 or header[:4] != bytes.fromhex('90abcdef'):
        raise ToolchainError('Invalid Dart kernel header')
    try:
        sdk_hash = header[8:18].decode('ascii')
    except UnicodeError as error:
        raise ToolchainError('Invalid Dart kernel SDK hash') from error
    if not re.fullmatch(r'[0-9a-f]{10}', sdk_hash):
        raise ToolchainError('Invalid Dart kernel SDK hash')
    if expected is not None and sdk_hash != expected:
        raise ToolchainError(f'Application kernel SDK hash {sdk_hash} does not match VM {expected}')
    return sdk_hash


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile')
    p.add_argument('--variant')
    p.add_argument('--app', type=Path)
    p.add_argument('--bundle-id', help='Require this exact App bundle ID before device installation')
    p.add_argument('--sdk-bin', action='store_true', help='Print only the verified SDK bin directory')
    args = p.parse_args()
    try:
        selection = Selection()
        sdk = selection.sdk()
        if args.sdk_bin:
            print(sdk / 'bin')
            return 0
        profile = args.profile or selection.lock['defaultProfile']
        engine = selection.engine(profile, args.variant)
        if args.bundle_id and not args.app:
            raise ToolchainError('--bundle-id requires --app')
        report = {'flutterSdk': str(sdk), 'flutterRevision': selection.lock['flutterRevision'],
                  'profile': profile, 'engine': engine}
        if args.app:
            report['bundleId'] = app_identity(args.app, args.bundle_id)
            if engine is None:
                raise ToolchainError('Embedded UUID comparison requires a local-engine profile')
            target = Path(engine['source']) / 'out' / engine['target'] / 'Flutter.framework/Flutter'
            embedded = args.app / 'Frameworks/Flutter.framework/Flutter'
            expected, actual = uuids(target), uuids(embedded)
            if expected != actual:
                raise ToolchainError(f'Embedded engine UUID mismatch: {actual}; expected {expected}')
            report['embeddedUuids'] = actual
            report['kernelSdkHash'] = kernel_sdk_hash(args.app, engine.get('dartSdkHash'))
        print(json.dumps(report, indent=2))
        return 0
    except (ToolchainError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print('Vyn toolchain: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
