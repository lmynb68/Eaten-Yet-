"""Run as the dedicated deployment user; never requires sudo."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

def verify_files(directory, assets):
    for asset in assets:
        path = directory / asset['name']
        if path.is_symlink() or not path.is_file() or path.stat().st_size != asset['bytes']:
            raise ValueError('Invalid APK size/type')
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != asset['sha256']:
            raise ValueError('APK checksum mismatch')


def write_json_atomic(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.release-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def activate(incoming, root):
    manifest = json.loads((incoming / 'release.json').read_text(encoding='utf-8-sig'))
    build = manifest['build']
    if type(build) is not int or build < 1 or len(manifest['assets']) != 2:
        raise ValueError('Invalid manifest')
    old_file = root / 'release.json'
    if old_file.exists():
        old = json.loads(old_file.read_text(encoding='utf-8-sig'))
        old_build = old.get('build') or int(old['tag'].split('+')[-1])
        if build < old_build:
            raise ValueError('Refusing downgrade')
        if build == old_build and manifest != old:
            # One-time migration from flat download URLs. APK identity must not change.
            legacy = json.loads(json.dumps(old))
            legacy['build'] = old_build
            for asset in legacy.get('assets', []):
                asset['url'] = f"downloads/build-{build}/{asset['name']}"
            if 'build' in old or legacy != manifest:
                raise ValueError('Build already published with different metadata')
    names = set()
    for asset in manifest['assets']:
        name = asset['name']
        if not re.fullmatch(r'[A-Za-z0-9.+_-]+\.apk', name) or name in names:
            raise ValueError('Invalid APK filename')
        names.add(name)
        if asset['url'] != f'downloads/build-{build}/{name}':
            raise ValueError('Unexpected download URL')
    downloads = root / 'downloads'
    downloads.mkdir(exist_ok=True)
    destination = downloads / f'build-{build}'
    if destination.exists():
        verify_files(destination, manifest['assets'])
    else:
        staging = Path(tempfile.mkdtemp(prefix='.upload-', dir=downloads))
        try:
            staging.chmod(0o755)
            for asset in manifest['assets']:
                source = incoming / asset['name']
                if source.is_symlink() or not source.is_file():
                    raise ValueError('Invalid APK type')
                target = staging / asset['name']
                shutil.copyfile(source, target)
                target.chmod(0o644)
            verify_files(staging, manifest['assets'])
            staging.rename(destination)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    if old_file.exists() and manifest == old:
        return
    # Files become visible first; the manifest is the final atomic switch.
    if old_file.exists():
        write_json_atomic(root / 'release.previous.json', old)
    write_json_atomic(old_file, manifest)

if __name__ == '__main__':
    import fcntl
    root = Path(sys.argv[2]).resolve()
    with (root / '.deploy.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        activate(Path(sys.argv[1]).resolve(), root)
    print('Verified APKs; website release metadata activated')

