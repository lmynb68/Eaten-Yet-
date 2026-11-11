import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

from archive_source import archive, validate_file


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'core.autocrlf', 'false')
        self.git('config', 'core.filemode', 'false')
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
                self.assertEqual(data, self.git('cat-file', 'blob', item['gitBlob']))
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


    def test_forced_tracked_dotenv_files_are_rejected(self):
        (self.repo / '.gitignore').write_text('.env*\n.ENV*\n', encoding='utf-8')
        self.commit()
        for name in ['.env', '.env.production', 'site/.env.local', '.ENV.Staging']:
            with self.subTest(name=name):
                path = self.repo / name
                path.write_text('EXAMPLE=not-a-secret\n', encoding='utf-8')
                self.git('add', '-f', name)
                self.commit()
                with self.assertRaisesRegex(ValueError, 'Generated or private'):
                    archive(self.repo, self.root / 'out')
                self.git('rm', name)
                self.commit()

    def test_unsafe_archive_paths_are_rejected(self):
        for name in ['../outside.txt', '/absolute.txt', 'C:/outside.txt', 'a\\..\\outside.txt']:
            with self.subTest(name=name):
                with self.assertRaisesRegex(ValueError, 'Generated or private'):
                    validate_file(name, b'example')

    def add_shell_fixture(self, attributes=''):
        self.git('config', 'core.autocrlf', 'true')
        script = self.repo / 'android/gradlew'
        script.write_bytes(b'#!/bin/sh\r\nprintf "archive fixture ok\\n"\r\n')
        if attributes:
            (self.repo / '.gitattributes').write_text(attributes, encoding='utf-8')
        self.git('add', '.')
        self.git('update-index', '--chmod=+x', 'android/gradlew')
        self.commit()
        # A Windows checkout remains clean with CRLF; Git objects contain LF.
        self.assertEqual(self.git('status', '--porcelain').strip(), b'')
        return self.git('show', 'HEAD:android/gradlew')

    def test_raw_blobs_preserve_lf_and_unix_executable_mode(self):
        raw = self.add_shell_fixture()
        self.assertNotIn(b'\r', raw)
        path = archive(self.repo, self.root / 'out')
        manifest = json.loads(path.read_text(encoding='utf-8'))
        with zipfile.ZipFile(path.parent / manifest['archive']) as source:
            self.assertEqual(source.read('android/gradlew'), raw)
            info = source.getinfo('android/gradlew')
            self.assertEqual(info.create_system, 3)
            self.assertEqual(info.external_attr >> 16, 0o100755)

    def test_export_and_eol_attributes_cannot_change_committed_content(self):
        (self.repo / 'docs/readme.md').write_text('$Format:%H$\n', encoding='utf-8')
        raw = self.add_shell_fixture(
            'android/gradlew text eol=crlf\ndocs/readme.md export-subst\nassets/menu.json export-ignore\n')
        path = archive(self.repo, self.root / 'out')
        manifest = json.loads(path.read_text(encoding='utf-8'))
        with zipfile.ZipFile(path.parent / manifest['archive']) as source:
            self.assertEqual(source.read('android/gradlew'), raw)
            self.assertEqual(source.read('docs/readme.md'), b'$Format:%H$\n')
            self.assertEqual(source.read('assets/menu.json'), b'assets/menu.json')
            for item in manifest['files']:
                self.assertEqual(source.read(item['path']), self.git('cat-file', 'blob', item['gitBlob']))

    @unittest.skipUnless(os.name == 'posix' and shutil.which('unzip'),
                         'Requires POSIX and unzip; runs in Linux CI.')
    def test_posix_unzip_can_run_archived_executable(self):
        self.add_shell_fixture()
        path = archive(self.repo, self.root / 'out')
        manifest = json.loads(path.read_text(encoding='utf-8'))
        target = self.root / 'extracted'
        subprocess.run(['unzip', '-q', str(path.parent / manifest['archive']), '-d', str(target)], check=True)
        result = subprocess.check_output([str(target / 'android/gradlew')], cwd=target)
        self.assertEqual(result, b'archive fixture ok\n')


if __name__ == '__main__':
    unittest.main()
