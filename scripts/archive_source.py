"""Archive every file at a clean Git HEAD, with a complete external manifest."""
import argparse
from datetime import datetime, timezone
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
    if (path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name or
            forbidden_parts.intersection(path.parts) or path.name in forbidden_names or
            path.name.lower() == '.env' or path.name.lower().startswith('.env.') or
            path.suffix.lower() in {'.apk', '.aab', '.zip', '.jks', '.keystore', '.pyc'}):
        raise ValueError(f'Generated or private file tracked: {name}')
    if re.search(rb'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----', data):
        raise ValueError(f'Private key content found: {name}')


def read_blobs(repo, object_ids):
    """Read committed bytes without checkout/archive EOL or attribute conversion."""
    ids = list(dict.fromkeys(object_ids))
    result = subprocess.run(
        ['git', '-C', str(repo), 'cat-file', '--batch'],
        input=('\n'.join(ids) + '\n').encode('ascii'),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    stream = io.BytesIO(result.stdout)
    blobs = {}
    for oid in ids:
        header = stream.readline().decode('ascii').strip().split()
        if len(header) != 3 or header[:2] != [oid, 'blob']:
            raise ValueError(f'Unable to read committed blob: {oid}')
        size = int(header[2])
        data = stream.read(size)
        if len(data) != size or stream.read(1) != b'\n':
            raise ValueError(f'Incomplete committed blob: {oid}')
        blobs[oid] = data
    if stream.read():
        raise ValueError('Unexpected trailing Git object data.')
    return blobs


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
    blobs = read_blobs(repo, (oid for mode, oid in expected.values()))
    # A commit timestamp, sorted paths, and fixed compression make repeated
    # archives independent of checkout mtimes, timezone, and core.autocrlf.
    timestamp = int(git(repo, 'show', '-s', '--format=%ct', commit).decode().strip())
    date = datetime.fromtimestamp(timestamp, timezone.utc)
    if date.year < 1980:
        date = datetime(1980, 1, 1, tzinfo=timezone.utc)
    elif date.year > 2107:
        date = datetime(2107, 12, 31, 23, 59, 58, tzinfo=timezone.utc)
    buffer = io.BytesIO()
    files = []
    with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
        for name, (mode, oid) in sorted(expected.items()):
            data = blobs[oid]
            validate_file(name, data)
            info = zipfile.ZipInfo(name, date.timetuple()[:6])
            info.create_system = 3  # Unix file type and executable bit from Git.
            info.external_attr = int(mode, 8) << 16
            target.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
            files.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                          'gitMode': mode, 'gitBlob': oid})
    payload = buffer.getvalue()
    output.mkdir(parents=True, exist_ok=True)
    zip_path = output / f'source-{commit[:12]}.zip'
    manifest_path = output / f'source-{commit[:12]}-manifest.json'
    if zip_path.exists() or manifest_path.exists():
        raise FileExistsError('Archive already exists; original artifacts will not be overwritten.')
    manifest = {'schemaVersion': 1, 'sourceCommit': commit, 'workingTreeClean': True,
                'contentPolicy': 'Unmodified Git blobs; checkout and export attributes are not applied.',
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
