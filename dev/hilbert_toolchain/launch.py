#!/usr/bin/env python3
"""Select the project's pinned framework and local iOS engine for CLI/IDE/Xcode."""
import json
import os
from pathlib import Path
import subprocess
import sys
from config import Selection, ToolchainError, project_root, revision, SDK_ROOT, NoProjectLock


def option(args, *names):
    for index, arg in enumerate(args):
        for name in names:
            if arg == name and index + 1 < len(args):
                return args[index + 1]
            if arg.startswith(name + '='):
                return arg.split('=', 1)[1]
    return None


def device_platform(args, sdk):
    device_id = option(args, '-d', '--device-id')
    env = dict(os.environ, HILBERT_FLUTTER_INNER='1')
    result = subprocess.run([str(sdk / 'bin/flutter'), 'devices', '--machine'],
                            env=env, capture_output=True, text=True, timeout=45)
    if result.returncode:
        raise ToolchainError('Cannot resolve target device: ' + result.stderr.strip())
    devices = json.loads(result.stdout)
    candidates = [d for d in devices if d.get('isSupported', False) and
                  (not device_id or d['id'] == device_id or d['id'].startswith(device_id))]
    if len(candidates) != 1:
        raise ToolchainError('Specify one connected device with -d; ambiguous/unknown target: ' + str(device_id))
    device = candidates[0]
    if device['targetPlatform'] != 'ios':
        return None
    return 'ios-simulator' if device.get('emulator') else 'ios-device'


def choose_variant(args, sdk, platform_lookup=device_platform):
    command = next((a for a in args if not a.startswith('-')), '')
    if command == 'build':
        if 'ios' not in args and 'ipa' not in args:
            return None
        platform = 'ios-simulator' if '--simulator' in args else 'ios-device'
        mode = 'debug' if platform == 'ios-simulator' else 'release'
    elif command in ('run', 'attach', 'drive'):
        platform = platform_lookup(args, sdk)
        if platform is None:
            return None
        mode = 'debug'
    else:
        return None
    for value in ('debug', 'profile', 'release'):
        if '--' + value in args:
            mode = value
    return platform + '-' + mode


def engine_for(selection, variant):
    profile = selection.lock.get('engineSelection', {}).get(variant)
    if profile is None:
        raise ToolchainError('No custom iOS engine for ' + variant + '; build/register this mode first. No upstream fallback.')
    return selection.engine(profile, variant)


def cli_arguments(selection, args, platform_lookup=device_platform):
    sdk = selection.sdk()
    if sdk != SDK_ROOT:
        raise ToolchainError('Invoked Flutter SDK differs from the project lock/registration')
    variant = choose_variant(args, sdk, platform_lookup)
    supplied = [a for a in args if a.startswith('--local-engine')]
    if variant is None:
        if supplied:
            raise ToolchainError('Local-engine overrides are not allowed for this command')
        return args
    engine = engine_for(selection, variant)
    expected = ['--local-engine-src-path=' + engine['source'],
                '--local-engine=' + engine['target'], '--local-engine-host=' + engine['host']]
    if supplied:
        if set(supplied) != set(expected):
            raise ToolchainError('Local-engine arguments conflict with the project lock')
        return args
    return expected + args


def xcode_environment(selection, env):
    selection.sdk()
    platform = 'ios-simulator' if env.get('PLATFORM_NAME') == 'iphonesimulator' else 'ios-device'
    mode = env.get('FLUTTER_BUILD_MODE', '').lower()
    if not mode:
        configuration = env.get('CONFIGURATION', '').lower()
        mode = next((v for v in ('debug', 'profile', 'release') if v in configuration), '')
    if not mode:
        raise ToolchainError('Cannot identify Xcode Flutter build mode')
    engine = engine_for(selection, platform + '-' + mode)
    env.update(FLUTTER_ENGINE=engine['source'], LOCAL_ENGINE=engine['target'],
               LOCAL_ENGINE_HOST=engine['host'])
    return env


def main():
    kind, *args = sys.argv[1:]
    try:
        # The custom SDK remains usable for SDK maintenance outside locked apps.
        try:
            root = project_root()
        except NoProjectLock:
            if kind == 'xcode':
                raise
            env = dict(os.environ, HILBERT_FLUTTER_INNER='1')
            os.execve(str(SDK_ROOT / 'bin/flutter'), [str(SDK_ROOT / 'bin/flutter'), *args], env)
        selection = Selection(root)
        if revision(SDK_ROOT) != selection.lock['flutterRevision']:
            raise ToolchainError('SDK commit does not match project toolchain.json')
        if kind == 'xcode':
            env = xcode_environment(selection, dict(os.environ))
            executable = SDK_ROOT / 'bin/dart'
            argv = [str(executable), str(SDK_ROOT / 'packages/flutter_tools/bin/xcode_backend.dart'), *args, 'ios']
        elif kind == 'print':
            print(json.dumps(cli_arguments(selection, args)))
            return 0
        else:
            env = dict(os.environ, HILBERT_FLUTTER_INNER='1')
            executable = SDK_ROOT / 'bin/flutter'
            argv = [str(executable), *cli_arguments(selection, args)]
        os.execve(str(executable), argv, env)
    except (ToolchainError, OSError, ValueError, subprocess.SubprocessError) as error:
        print('Hilbert Flutter: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
