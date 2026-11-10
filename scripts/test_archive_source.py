import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

from archive_source import archive


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        for name in ['site/index.html', 'android/build.gradle', 'scripts/check.py',
                     'docs/readme.md', 'lib/main.dart', 'assets/menu.json', 'pubspec.lock']:
            p = self.repo / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(name, encoding='utf-8')
        self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.STDOUT)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Archive test', '-c', 'user.email=test@example.invalid',
                 'commit', '-qm', 'fixture')

    def test_all_committed_files_are_hashed_and_archive_is_repeatable(self):
        path = archive(self.repo, self.root / 'one')
        first = json.loads(path.read_text(encoding='utf-8'))
        second = json.loads(archive(self.repo, self.root / 'two').read_text(encoding='utf-8'))
        self.assertEqual(first, second)
        self.assertEqual(first['fileCount'], 7)
        with zipfile.ZipFile(path.parent / first['archive']) as source:
            for item in first['files']:
                data = source.read(item['path'])
                self.assertEqual(item['sha256'], hashlib.sha256(data).hexdigest())
                self.assertEqual(item['bytes'], len(data))
        with self.assertRaises(FileExistsError):
            archive(self.repo, self.root / 'one')

    def test_untracked_or_modified_sources_are_rejected(self):
        (self.repo / 'new.dart').write_text('uncommitted')
        with self.assertRaisesRegex(ValueError, 'working changes'):
            archive(self.repo, self.root / 'out')

    def test_tracked_generated_files_are_rejected(self):
        (self.repo / '.flutter-plugins-dependencies').write_text('{}')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'Generated or private'):
            archive(self.repo, self.root / 'out')

    def test_tracked_signing_config_is_rejected(self):
        (self.repo / 'android/key.properties').write_text('not real credentials')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'Generated or private'):
            archive(self.repo, self.root / 'out')


if __name__ == '__main__':
    unittest.main()
