"""Validate published APKs using Android build-tools, then create website metadata."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

CERT = 'ba897c5fa7a0b3e55c828d0e6b17b1f9640dfda37b07accce1b29e53b99a17ef'

def verify_architectures(apk, expected):
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
    # Plugins can include unused ABIs; the Flutter engine AND app determine support.
    for library in ('libapp.so', 'libflutter.so'):
        actual = {name.split('/')[1] for name in names
                  if re.fullmatch(r'lib/[^/]+/' + re.escape(library), name)}
        if actual != expected:
            raise ValueError(f'Unexpected APK architectures for {library}: {sorted(actual)}')

def prepare(folder, release, tools):
    if release['draft'] or release['prerelease']:
        raise ValueError('Only published stable releases are allowed')
    assets = []
    identity = None
    for kind, abi in [('arm64', 'arm64-v8a'), ('universal', 'arm64-v8a, armeabi-v7a, x86_64')]:
        matches = list(folder.glob(f'EatenYet-*-android-{kind}.apk'))
        if len(matches) != 1:
            raise ValueError(f'Expected exactly one {kind} APK')
        apk = matches[0]
        if not re.fullmatch(r'[A-Za-z0-9.+_-]+\.apk', apk.name):
            raise ValueError('Unsafe filename')
        signature = subprocess.check_output([str(tools / 'apksigner'), 'verify', '--print-certs', str(apk)], text=True)
        if f'certificate SHA-256 digest: {CERT}' not in signature:
            raise ValueError('Wrong signing certificate')
        info = subprocess.check_output([str(tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
        match = re.search(r"(?m)^package: name='([^']+)' versionCode='(\d+)' versionName='(\d+\.\d+\.\d+)'", info)
        if not match or match[1] != 'local.eatwhat.campus' or 'application-debuggable' in info or "sdkVersion:'24'" not in info:
            raise ValueError('Unexpected APK identity, debug flag or minimum SDK')
        expected = set(abi.replace(' ', '').split(','))
        verify_architectures(apk, expected)
        current = (int(match[2]), match[3])
        if identity and identity != current:
            raise ValueError('APK versions differ')
        identity = current
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        remote = next(a for a in release['assets'] if a['name'] == apk.name)
        if remote['size'] != apk.stat().st_size or remote.get('digest') != 'sha256:' + digest:
            raise ValueError('GitHub asset digest/size mismatch or missing digest')
        assets.append(dict(name=apk.name, abi=abi, bytes=apk.stat().st_size, sha256=digest,
                           url=f'downloads/build-{identity[0]}/{apk.name}'))
    if release['tag_name'] != f'v{identity[1]}+{identity[0]}':
        raise ValueError('Tag must be vVERSION+BUILD and match APK')
    result = dict(status='published', version=identity[1], build=identity[0], tag=release['tag_name'],
                  publishedAt=release['published_at'], minAndroid='7.0 (API 24)', assets=assets)
    (folder / 'release.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    prepare(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text()), Path(os.environ['BUILD_TOOLS']))
