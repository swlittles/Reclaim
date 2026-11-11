#!/usr/bin/env python3
import os, pathlib, re, subprocess
version = pathlib.Path('VERSION').read_text().strip()
build = int(pathlib.Path('BUILD_NUMBER').read_text().strip())
assert re.fullmatch(r'\d+\.\d+\.\d+', version) and build > 0
assert os.environ.get('RELEASE_TAG', 'v' + version) == 'v' + version
assert '## ' + version in pathlib.Path('CHANGELOG.md').read_text()
tags = subprocess.check_output(['git', 'tag', '--list', 'v*'], text=True).splitlines()
for tag in tags:
    if tag == 'v' + version:
        continue
    prior = subprocess.run(['git', 'show', tag + ':BUILD_NUMBER'], capture_output=True, text=True)
    if prior.returncode == 0:
        assert build > int(prior.stdout.strip()), 'BUILD_NUMBER must exceed every existing release'
print('Version, tag, changelog, and monotonic build validated.')
