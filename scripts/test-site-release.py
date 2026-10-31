import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('activate', Path(__file__).with_name('activate-site-release.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
prepare_spec = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare-site-release.py'))
prepare_module = importlib.util.module_from_spec(prepare_spec)
prepare_spec.loader.exec_module(prepare_module)

class ArchitectureTests(unittest.TestCase):
    def test_plugin_extra_abis_are_not_app_abis(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as directory:
            apk = Path(directory) / 'sample.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                for name in ('lib/arm64-v8a/libapp.so', 'lib/arm64-v8a/libflutter.so',
                             'lib/x86_64/libdatastore_shared_counter.so'):
                    archive.writestr(name, b'fixture')
            prepare_module.verify_architectures(apk, {'arm64-v8a'})
            with self.assertRaises(ValueError):
                prepare_module.verify_architectures(apk, {'arm64-v8a', 'x86_64'})

    def test_missing_engine_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as directory:
            apk = Path(directory) / 'sample.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libapp.so', b'fixture')
            with self.assertRaises(ValueError):
                prepare_module.verify_architectures(apk, {'arm64-v8a'})

class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent)
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root = base / 'site'
        self.root.mkdir()
        self.incoming = base / 'incoming'
        self.incoming.mkdir()
        self.old = {'tag': 'v1.0.0+25'}
        (self.root / 'release.json').write_text(json.dumps(self.old))
        self.manifest = {'build': 27, 'assets': []}
        for kind in ['arm64', 'universal']:
            name = f'EatenYet-v1.0.0-build27-android-{kind}.apk'
            data = kind.encode()
            (self.incoming / name).write_bytes(data)
            self.manifest['assets'].append(dict(name=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), url=f'downloads/build-27/{name}'))
        self.save()

    def save(self):
        (self.incoming / 'release.json').write_text(json.dumps(self.manifest))

    def test_success_and_retry(self):
        module.activate(self.incoming, self.root)
        self.assertEqual(json.loads((self.root / 'release.previous.json').read_text()), self.old)
        module.activate(self.incoming, self.root)
        self.assertEqual(json.loads((self.root / 'release.previous.json').read_text()), self.old)
        for asset in self.manifest['assets']:
            self.assertTrue((self.root / asset['url']).exists())

    def test_corruption_preserves_old(self):
        (self.incoming / self.manifest['assets'][1]['name']).write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            module.activate(self.incoming, self.root)
        self.assertEqual(json.loads((self.root / 'release.json').read_text()), self.old)
        self.assertFalse((self.root / 'downloads').exists())

    def test_downgrade_rejected(self):
        self.manifest['build'] = 24
        self.save()
        with self.assertRaises(ValueError):
            module.activate(self.incoming, self.root)

    def test_path_traversal_rejected(self):
        self.manifest['assets'][0]['name'] = '../escape.apk'
        self.save()
        with self.assertRaises(ValueError):
            module.activate(self.incoming, self.root)

    def test_existing_build_conflict(self):
        module.activate(self.incoming, self.root)
        self.manifest['assets'][0]['sha256'] = '0' * 64
        self.save()
        with self.assertRaises(ValueError):
            module.activate(self.incoming, self.root)

    def test_legacy_urls_migrate_without_changing_apks(self):
        legacy = json.loads(json.dumps(self.manifest))
        del legacy['build']
        legacy['tag'] = 'v1.0.0+27'
        self.manifest['tag'] = legacy['tag']
        for asset in legacy['assets']:
            asset['url'] = 'downloads/' + asset['name']
        (self.root / 'release.json').write_text(json.dumps(legacy))
        self.save()
        module.activate(self.incoming, self.root)
        self.assertEqual(json.loads((self.root / 'release.previous.json').read_text()), legacy)
        self.assertEqual(json.loads((self.root / 'release.json').read_text()), self.manifest)

if __name__ == '__main__':
    unittest.main()

