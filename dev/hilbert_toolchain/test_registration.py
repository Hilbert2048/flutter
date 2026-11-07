import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class RegistrationTest(unittest.TestCase):
    def test_atomic_registration_preserves_shared_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / 'sdk'
            (sdk / 'bin').mkdir(parents=True)
            (sdk / 'bin/flutter').write_text('#!/bin/sh\n')
            subprocess.run(['git', 'init', '-q', str(sdk)], check=True)
            subprocess.run(['git', '-C', str(sdk), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(sdk), '-c', 'user.name=Toolchain Fixture',
                            '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                            'commit', '-qm', 'fixture'], check=True)
            revision = subprocess.check_output(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], text=True).strip()
            app = root / 'app'
            (app / '.toolchains').mkdir(parents=True)
            (app / 'toolchain.json').write_text(json.dumps({'schema': 2, 'flutterRevision': revision}))
            shared = root / 'shared.json'
            shared.write_text('{}')
            link = app / '.toolchains/local.json'
            link.symlink_to(shared)
            env = dict(os.environ, HILBERT_PROJECT_ROOT=str(app))
            env.pop('HILBERT_TOOLCHAIN_CONFIG', None)
            env.pop('VYN_TOOLCHAIN_CONFIG', None)
            subprocess.run([sys.executable, str(Path(__file__).with_name('prepare.py')),
                            '--sdk', str(sdk)], cwd=app, env=env, capture_output=True, check=True)
            self.assertTrue(link.is_symlink())
            self.assertEqual(json.loads(shared.read_text())['flutterSdk'], str(sdk.resolve()))


if __name__ == '__main__':
    unittest.main()
