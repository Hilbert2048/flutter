"""Project-local SDK/engine selection. This module never mutates an SDK cache."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

SDK_ROOT = Path(__file__).resolve().parents[2]


def project_root(start=None):
    if os.environ.get('HILBERT_PROJECT_ROOT'):
        return Path(os.environ['HILBERT_PROJECT_ROOT']).resolve()
    start = Path(start or Path.cwd()).resolve()
    for candidate in (start, *start.parents):
        lock = candidate / 'toolchain.json'
        if lock.is_file() and read_json(lock).get('schema') == 2:
            return candidate
    raise NoProjectLock('No custom Flutter toolchain.json found from ' + str(start))


ROOT = Path(os.environ.get('HILBERT_PROJECT_ROOT', Path.cwd())).resolve()


class ToolchainError(Exception):
    pass


class NoProjectLock(ToolchainError):
    pass


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise ToolchainError(f'Cannot read {path}: {error}') from error


def revision(directory):
    result = subprocess.run(['git', '-C', str(directory), 'rev-parse', 'HEAD'],
                            capture_output=True, text=True)
    if result.returncode:
        raise ToolchainError(f'Not a Git checkout: {directory}')
    return result.stdout.strip()


def clean_source(directory):
    result = subprocess.run(['git', '-C', str(directory), 'diff', 'HEAD', '--name-only'],
                            capture_output=True, text=True, check=True)
    if result.stdout.strip():
        raise ToolchainError('Toolchain tracked sources differ from the pinned commit: ' +
                             result.stdout.strip())


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def engine_file(source, relative):
    path = (source / relative).resolve()
    if not path.is_relative_to(source.resolve()) or not path.is_file():
        raise ToolchainError(f'Missing or out-of-tree engine artifact: {relative}')
    return path


def output_name(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', value):
        raise ToolchainError(f'Invalid engine output name: {value!r}')
    return value


def verify_dependencies(source, pin):
    # DEPS checkouts are separate repositories; a clean engine HEAD alone does
    # not prove their identity (notably the build-only Dart SDK compatibility patch).
    for dependency in pin.get('dependencies', []):
        path = (source / dependency['path']).resolve()
        if not path.is_relative_to(source.resolve()):
            raise ToolchainError('Dependency path escapes the engine source')
        if revision(path) != dependency['revision']:
            raise ToolchainError(f'Engine dependency revision mismatch: {dependency["path"]}')
        clean_source(path)


def verify_sdk_identity(source, pin, variant):
    expected = pin.get('dartSdkHash')
    if expected is None:
        return
    sdk_revision = engine_file(source, f'out/{output_name(variant["host"])}/dart-sdk/revision')
    if sdk_revision.read_text().strip()[:10] != expected:
        raise ToolchainError('Host Dart SDK hash does not match the engine VM SDK hash')
    version = engine_file(source, f'out/{output_name(variant["target"])}/gen/flutter/third_party/dart/runtime/version.cc')
    match = re.search(r'Version::git_short_hash_\s*=\s*"([0-9a-f]{10})"', version.read_text())
    if match is None or match.group(1) != expected:
        raise ToolchainError('Generated VM SDK hash does not match the engine manifest')


class Selection:
    def __init__(self, root=None, local_path=None):
        root = Path(root) if root is not None else project_root()
        self.root = root
        project_pin = read_json(root / 'toolchain.json')
        self.lock = project_pin if project_pin.get('schema') == 2 else read_json(root / 'tool/engine/manifest.json')
        if self.lock.get('schema') not in (1, 2):
            raise ToolchainError('Unsupported engine manifest schema')
        pinned_sdk = read_json(root / 'toolchain.json')['flutterRevision']
        if self.lock['flutterRevision'] != pinned_sdk:
            raise ToolchainError('Engine manifest and toolchain.json disagree')
        self.local_path = local_path or Path(os.environ.get(
            'HILBERT_TOOLCHAIN_CONFIG') or os.environ.get('VYN_TOOLCHAIN_CONFIG') or root / '.toolchains/local.json')
        self.local = read_json(self.local_path) if self.local_path.exists() else {}

    def sdk(self):
        raw = os.environ.get('HILBERT_FLUTTER_SDK') or os.environ.get('VYN_FLUTTER_SDK') or self.local.get('flutterSdk') or self.root / '.toolchains/flutter'
        if not raw:
            raise ToolchainError('Configure .toolchains/flutter or HILBERT_FLUTTER_SDK')
        sdk = Path(raw).expanduser().resolve()
        if revision(sdk) != self.lock['flutterRevision']:
            raise ToolchainError('Flutter SDK revision does not match toolchain.json')
        clean_source(sdk)
        if not (sdk / 'bin/flutter').is_file():
            raise ToolchainError(f'Missing flutter executable in {sdk}')
        return sdk

    def engine(self, profile, variant):
        profiles = self.lock['profiles']
        if profile not in profiles:
            raise ToolchainError(f'Unknown engine profile: {profile}')
        pin = profiles[profile]
        if pin['kind'] == 'upstream':
            return None
        if variant not in pin['variants']:
            raise ToolchainError(f'Engine {profile} has no validated build configuration {variant}')
        registration = self.local.get('engines', {}).get(profile)
        if registration is None:
            raise ToolchainError(f'Engine {profile} is not registered on this machine')
        source = Path(registration['source']).resolve()
        if revision(source) != pin['sourceRevision']:
            raise ToolchainError('Engine source revision does not match its manifest')
        clean_source(source)
        verify_dependencies(source, pin)
        artifact = registration.get('variants', {}).get(variant)
        if artifact is None:
            raise ToolchainError(f'Missing local engine variant: {variant}')
        if artifact.get('sourceRevision') != pin['sourceRevision']:
            raise ToolchainError('Artifact registration is stale for this engine commit')
        expected = pin['variants'][variant]
        verify_sdk_identity(source, pin, expected)
        for field in ('target', 'host'):
            if artifact[field] != expected[field]:
                raise ToolchainError(f'Incorrect {field} output for {variant}')
            output_name(artifact[field])
        files = artifact.get('files', {})
        required = expected['requiredFiles']
        if not required or not set(required).issubset(files):
            raise ToolchainError('Artifact registration omits required engine/host files')
        for relative, checksum in files.items():
            if digest(engine_file(source, relative)) != checksum:
                raise ToolchainError(f'Engine artifact changed after registration: {relative}')
        result = {'source': str(source), 'target': artifact['target'],
                  'host': artifact['host'], 'revision': pin['sourceRevision']}
        if pin.get('dartSdkHash'):
            result['dartSdkHash'] = pin['dartSdkHash']
        return result
