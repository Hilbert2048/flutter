#!/usr/bin/env python3
"""Register an existing private SDK/build. Does not download, build or install."""
import argparse
import json
import os
from pathlib import Path
import sys
from config import Selection, ToolchainError, clean_source, digest, engine_file, revision, verify_dependencies, verify_sdk_identity


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sdk', type=Path)
    p.add_argument('--profile')
    p.add_argument('--variant')
    p.add_argument('--engine-src', type=Path)
    args = p.parse_args()
    try:
        selection = Selection()
        local = dict(selection.local)
        if args.sdk:
            sdk = args.sdk.expanduser().resolve()
            if revision(sdk) != selection.lock['flutterRevision']:
                raise ToolchainError('SDK revision does not match the project pin')
            if not (sdk / 'bin/flutter').is_file():
                raise ToolchainError('SDK has no flutter executable')
            clean_source(sdk)
            local['flutterSdk'] = str(sdk)
        if any((args.profile, args.variant, args.engine_src)):
            if not all((args.profile, args.variant, args.engine_src)):
                raise ToolchainError('--profile, --variant and --engine-src are required together')
            pin = selection.lock['profiles'][args.profile]
            variant = pin['variants'][args.variant]
            source = args.engine_src.resolve()
            if revision(source) != pin['sourceRevision']:
                raise ToolchainError('Engine source revision differs from the pin')
            clean_source(source)
            verify_dependencies(source, pin)
            verify_sdk_identity(source, pin, variant)
            files = {relative: digest(engine_file(source, relative))
                     for relative in variant['requiredFiles']}
            if variant.get('artifactFiles') is not None and files != variant['artifactFiles']:
                raise ToolchainError('Build differs from committed artifact hashes; publish a new reviewed lock')
            entry = local.setdefault('engines', {}).setdefault(args.profile, {})
            if entry.get('source') not in (None, str(source)):
                raise ToolchainError('Profile already refers to a different source checkout')
            entry['source'] = str(source)
            entry.setdefault('variants', {})[args.variant] = {
                'sourceRevision': pin['sourceRevision'], 'target': variant['target'],
                'host': variant['host'], 'files': files}
        if not args.sdk and not args.profile:
            p.error('Specify --sdk or a complete local-engine registration')
        destination = selection.local_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + '.tmp')
        temporary.write_text(json.dumps(local, indent=2) + '\n')
        os.replace(temporary, destination)
        print(destination)
        return 0
    except (ToolchainError, KeyError, OSError) as error:
        print('Vyn toolchain: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
