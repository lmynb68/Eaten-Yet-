"""Run as the dedicated deployment user; never requires sudo."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

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
        path = incoming / name
        if path.is_symlink() or path.stat().st_size != asset['bytes']:
            raise ValueError('Invalid APK size/type')
        if hashlib.sha256(path.read_bytes()).hexdigest() != asset['sha256']:
            raise ValueError('APK checksum mismatch')
        if asset['url'] != f'downloads/build-{build}/{name}':
            raise ValueError('Unexpected download URL')
    downloads = root / 'downloads'
    downloads.mkdir(exist_ok=True)
    destination = downloads / f'build-{build}'
    if destination.exists():
        for asset in manifest['assets']:
            if hashlib.sha256((destination / asset['name']).read_bytes()).hexdigest() != asset['sha256']:
                raise ValueError('Existing build differs')
    else:
        staging = Path(tempfile.mkdtemp(prefix='.upload-', dir=downloads))
        try:
            staging.chmod(0o755)
            for asset in manifest['assets']:
                target = staging / asset['name']
                shutil.copyfile(incoming / asset['name'], target)
                target.chmod(0o644)
            staging.rename(destination)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    if old_file.exists() and manifest == old:
        return
    # Files become visible first; the manifest is the final atomic switch.
    if old_file.exists():
        shutil.copyfile(old_file, root / 'release.previous.json')
    fd, temp = tempfile.mkstemp(prefix='.release-', dir=root)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(manifest, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, 0o644)
        os.replace(temp, old_file)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

if __name__ == '__main__':
    import fcntl
    root = Path(sys.argv[2]).resolve()
    with (root / '.deploy.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        activate(Path(sys.argv[1]).resolve(), root)
    print('Verified APKs; website release metadata activated')

