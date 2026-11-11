#!/usr/bin/env python3
import base64, pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1]); variant = sys.argv[2]
p = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
dev = variant == 'development'
assert p['CFBundleIdentifier'] == ('io.github.swlittles.Reclaim.dev' if dev else 'io.github.swlittles.Reclaim')
assert p['CFBundleName'] == ('Reclaim Dev' if dev else 'Reclaim')
assert p['LSUIElement'] is True
assert p['LSMinimumSystemVersion'] == '13.0'
assert (app / 'Contents/Resources/Reclaim.icns').is_file()
assert (app / 'Contents/Frameworks/Sparkle.framework').is_dir()
if dev:
    assert 'SUFeedURL' not in p and 'SUPublicEDKey' not in p
else:
    assert len(base64.b64decode(p['SUPublicEDKey'], validate=True)) == 32
    assert p['SURequireSignedFeed'] and p['SUVerifyUpdateBeforeExtraction']
    assert not p['SUAutomaticallyUpdate'] and not p['SUEnableSystemProfiling']
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('Verified bundle identity, resources, updater configuration and signature.')
