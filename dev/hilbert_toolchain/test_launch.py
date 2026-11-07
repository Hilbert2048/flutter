import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import launch
from config import project_root, ToolchainError


class SelectionFixture:
    root = Path('/project')
    lock = {'engineSelection': {'ios-device-release': 'restore', 'ios-simulator-debug': 'sim'}}

    def sdk(self):
        return launch.SDK_ROOT

    def engine(self, profile, variant):
        return {'source': '/engine source', 'target': variant, 'host': 'host-matched'}


class LaunchTest(unittest.TestCase):
    def test_cli_ide_device_release_uses_paired_engine(self):
        args = ['run', '--machine', '--release', '-d', 'phone']
        actual = launch.cli_arguments(SelectionFixture(), args, lambda *_: 'ios-device')
        self.assertEqual(actual[:3], ['--local-engine-src-path=/engine source',
                         '--local-engine=ios-device-release', '--local-engine-host=host-matched'])
        self.assertEqual(actual[3:], args)

    def test_ios_build_defaults_to_release(self):
        self.assertEqual(launch.choose_variant(['build', 'ios'], Path('/sdk')), 'ios-device-release')
        self.assertEqual(launch.choose_variant(['build', 'ipa'], Path('/sdk')), 'ios-device-release')

    def test_simulator_defaults_to_debug(self):
        self.assertEqual(launch.choose_variant(['build', 'ios', '--simulator'], Path('/sdk')),
                         'ios-simulator-debug')

    def test_other_platform_keeps_framework_without_ios_engine(self):
        self.assertEqual(launch.cli_arguments(SelectionFixture(), ['build', 'apk']), ['build', 'apk'])
        self.assertEqual(launch.cli_arguments(SelectionFixture(), ['run'], lambda *_: None), ['run'])

    def test_missing_mode_cannot_fall_back(self):
        with self.assertRaisesRegex(ToolchainError, 'No upstream fallback'):
            launch.cli_arguments(SelectionFixture(), ['build', 'ios', '--profile'])

    def test_xcode_ignores_stale_generated_engine(self):
        env = {'PLATFORM_NAME': 'iphoneos', 'CONFIGURATION': 'Release-production',
               'LOCAL_ENGINE': 'stale', 'LOCAL_ENGINE_HOST': 'wrong'}
        with patch('launch.validate_package_sdk'):
            actual = launch.xcode_environment(SelectionFixture(), env)
        self.assertEqual(actual['LOCAL_ENGINE'], 'ios-device-release')
        self.assertEqual(actual['LOCAL_ENGINE_HOST'], 'host-matched')

    def test_xcode_simulator_selects_debug(self):
        with patch('launch.validate_package_sdk'):
            actual = launch.xcode_environment(SelectionFixture(),
                         {'PLATFORM_NAME': 'iphonesimulator', 'CONFIGURATION': 'Debug'})
        self.assertEqual(actual['LOCAL_ENGINE'], 'ios-simulator-debug')

    def test_xcode_rejects_stale_framework_package_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / '.dart_tool').mkdir()
            config = root / '.dart_tool/package_config.json'
            config.write_text(json.dumps({'packages': [{'name': 'flutter', 'rootUri': 'file:///old-sdk/packages/flutter'}]}))
            with self.assertRaisesRegex(ToolchainError, 'another Flutter SDK'):
                launch.validate_package_sdk(root, Path('/new-sdk'))
            config.write_text(json.dumps({'packages': [{'name': 'flutter', 'rootUri': 'file:///new-sdk/packages/flutter'}]}))
            launch.validate_package_sdk(root, Path('/new-sdk'))

    def test_xcode_assemble_accepts_exact_locked_engine(self):
        flags = ['--local-engine-src-path=/engine source', '--local-engine=ios-device-release',
                 '--local-engine-host=host-matched']
        args = flags + ['assemble', '-dTargetPlatform=ios', '-dBuildMode=release',
                        '-dSdkRoot=/Xcode/iPhoneOS27.2.sdk', 'release_ios_bundle_flutter_assets']
        self.assertEqual(launch.cli_arguments(SelectionFixture(), args), args)

    def test_simulator_assemble_resolves_from_sdk_root(self):
        self.assertEqual(launch.choose_variant(['assemble', '-dTargetPlatform=ios', '-dBuildMode=debug',
                         '-dSdkRoot=/Xcode/iPhoneSimulator27.2.sdk'], Path('/sdk')), 'ios-simulator-debug')

    def test_flutter_does_not_inherit_xcode_engine_environment(self):
        with patch.dict(os.environ, {'FLUTTER_ENGINE': '/stale', 'LOCAL_ENGINE': 'stale',
                                    'LOCAL_ENGINE_HOST': 'wrong'}):
            env = launch.flutter_environment()
            self.assertNotIn('FLUTTER_ENGINE', env)
            self.assertNotIn('LOCAL_ENGINE', env)
            self.assertNotIn('LOCAL_ENGINE_HOST', env)

    def test_external_override_is_rejected(self):
        with self.assertRaisesRegex(ToolchainError, 'conflict'):
            launch.cli_arguments(SelectionFixture(), ['--local-engine=other', 'build', 'ios'])

    def test_corrupt_project_lock_does_not_become_unlocked(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {}, clear=True):
            Path(tmp, 'toolchain.json').write_text('{broken')
            with self.assertRaisesRegex(ToolchainError, 'Cannot read'):
                project_root(tmp)

    def test_ios_device_resolution_uses_selected_id_and_platform(self):
        devices = [{'id': 'sim-123', 'isSupported': True, 'targetPlatform': 'ios', 'emulator': True},
                   {'id': 'android', 'isSupported': True, 'targetPlatform': 'android-arm64'}]
        with patch('launch.subprocess.run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps(devices)
            self.assertEqual(launch.device_platform(['-d', 'sim-123'], Path('/sdk')), 'ios-simulator')
            self.assertIsNone(launch.device_platform(['-d', 'android'], Path('/sdk')))
            with self.assertRaisesRegex(ToolchainError, 'Specify one'):
                launch.device_platform([], Path('/sdk'))


if __name__ == '__main__':
    unittest.main()
