"""Archive every file at a clean Git HEAD, with a complete external manifest."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import zipfile


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def validate_file(name, data):
    path = PurePosixPath(name)
    forbidden_parts = {'.git', '.dart_tool', '.gradle', 'build', 'logs',
                       '__pycache__', 'node_modules', '.pub-cache', '.local-deploy'}
    forbidden_names = {'key.properties', 'local.properties',
                       '.flutter-plugins-dependencies', 'browser-qa-result.json'}
    if (path.is_absolute() or '..' in path.parts or
            forbidden_parts.intersection(path.parts) or path.name in forbidden_names or
            path.suffix.lower() in {'.apk', '.aab', '.zip', '.jks', '.keystore', '.pyc'}):
        raise ValueError(f'Generated or private file tracked: {name}')
    if re.search(rb'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----', data):
        raise ValueError(f'Private key content found: {name}')


def archive(repo, output):
    repo, output = Path(repo).resolve(), Path(output).resolve()
    if output == repo or repo in output.parents:
        raise ValueError('Output must be outside the source checkout.')
    if git(repo, 'status', '--porcelain', '--untracked-files=all').strip():
        raise ValueError('Commit or preserve working changes before archiving.')
    commit = git(repo, 'rev-parse', 'HEAD').decode().strip()
    tree = git(repo, 'ls-tree', '-r', '-z', commit).split(b'\0')
    expected = {}
    for entry in filter(None, tree):
        meta, name = entry.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        if kind != 'blob' or mode not in {'100644', '100755'}:
            raise ValueError('Submodules and symlinks require a separate archival policy.')
        expected[name.decode('utf-8')] = (mode, oid)
    payload = git(repo, 'archive', '--format=zip', commit)
    files = []
    with zipfile.ZipFile(io.BytesIO(payload)) as source:
        names = [item.filename for item in source.infolist() if not item.is_dir()]
        if set(names) != set(expected) or len(names) != len(expected):
            raise ValueError('Archive differs from Git tree (check export-ignore attributes).')
        for name in sorted(names):
            data = source.read(name)
            validate_file(name, data)
            mode, oid = expected[name]
            files.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                          'gitMode': mode, 'gitBlob': oid})
    output.mkdir(parents=True, exist_ok=True)
    zip_path = output / f'source-{commit[:12]}.zip'
    manifest_path = output / f'source-{commit[:12]}-manifest.json'
    if zip_path.exists() or manifest_path.exists():
        raise FileExistsError('Archive already exists; original artifacts will not be overwritten.')
    manifest = {'schemaVersion': 1, 'sourceCommit': commit, 'workingTreeClean': True,
                'archive': zip_path.name, 'archiveSha256': hashlib.sha256(payload).hexdigest(),
                'fileCount': len(files), 'files': files}
    zip_path.write_bytes(payload)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return manifest_path


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(archive(args.repo, args.output))
