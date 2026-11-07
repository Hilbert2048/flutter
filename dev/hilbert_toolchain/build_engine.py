#!/usr/bin/env python3
"""Build new isolated engine outputs with an explicitly matching source Dart SDK."""
import argparse
from pathlib import Path
import runpy
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--mode', choices=['debug', 'profile', 'release'], required=True)
    parser.add_argument('--host', action='store_true')
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    source = args.source.resolve()
    if not args.output.replace('_', '').isalnum():
        parser.error('Output must be a single GN directory name')
    output = source / 'out' / args.output
    if output.exists():
        parser.error('Refusing to regenerate an existing output; resume its ninja command instead')
    gn = runpy.run_path(str(source / 'flutter/tools/gn'))
    options = ['--runtime-mode=' + args.mode, '--no-goma', '--no-rbe', '--no-lto',
               '--no-enable-unittests', '--no-build-embedder-examples']
    options += ['--mac-cpu=arm64'] if args.host else ['--ios']
    parsed = gn['parse_args'](options)
    values = gn['to_gn_args'](parsed)
    if args.host:
        values.update(flutter_prebuilt_dart_sdk=False, dart_sdk_output='dart-sdk')
    output.mkdir(parents=True)
    (output / 'args.gn').write_text('\n'.join(gn['to_command_line'](values)) + '\n')
    subprocess.run([str(source / 'flutter/third_party/gn/gn'), 'gen', str(output),
                    '--script-executable=' + sys.executable], cwd=source, check=True)
    targets = ['flutter/third_party/dart/sdk:create_most_sdk', 'flutter/sky/packages/sky_engine',
               'frontend_server_aot.dart.snapshot', 'font-subset', 'flutter/tools/const_finder'] if args.host else [
                   'flutter_framework', 'flutter_patched_sdk/platform_strong.dill',
                   'flutter/lib/snapshot:generate_snapshot_bins']
    subprocess.run(['ninja', '-C', str(output), '-j' + str(args.jobs), *targets], cwd=source, check=True)


if __name__ == '__main__':
    main()
