#!/usr/bin/env python3
"""Verify a distribution IPA's identity, signature, and declared capabilities."""

import argparse
import plistlib
import subprocess
import tempfile
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--build', required=True)
    args = parser.parse_args()
    expected = plistlib.loads((Path(__file__).resolve().parent.parent / 'Resources/Lifting.entitlements').read_bytes())

    with tempfile.TemporaryDirectory(prefix='torque-ipa-check-') as directory:
        root = Path(directory)
        with zipfile.ZipFile(args.ipa) as archive:
            archive.extractall(root)
        apps = list((root / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise SystemExit('Expected exactly one application in the IPA.')
        app = apps[0]
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True)
        entitlements = plistlib.loads(result.stdout)
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        checks = {
            'bundle identity': info.get('CFBundleIdentifier') == 'local.lifting.app',
            'display name': info.get('CFBundleDisplayName') == 'Setform',
            'build number': info.get('CFBundleVersion') == args.build,
            'distribution signing': entitlements.get('get-task-allow') is False,
        }
        for key, value in expected.items():
            checks[key] = entitlements.get(key) == value
        failed = [name for name, passed in checks.items() if not passed]
        if failed:
            raise SystemExit('IPA validation failed: ' + ', '.join(failed))
        print(f'Verified Setform build {args.build}: signature, identity, and capabilities.')


if __name__ == '__main__':
    main()
