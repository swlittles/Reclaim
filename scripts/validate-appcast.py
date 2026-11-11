#!/usr/bin/env python3
"""Validate the generated enclosure against the exact final distribution asset.
Cryptographic verification is performed separately by Sparkle's sign_update.
"""
import base64
import pathlib
import sys
import xml.etree.ElementTree as ET

def validate(path, version, build, dmg):
    root = ET.parse(path).getroot()
    items = root.findall('./channel/item')
    assert len(items) == 1, 'Expected one current release item'
    item = items[0]
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    assert item.findtext('sparkle:version', namespaces=ns) == str(build), 'Wrong build'
    assert item.findtext('sparkle:shortVersionString', namespaces=ns) == version, 'Wrong version'
    assert item.findtext('sparkle:minimumSystemVersion', namespaces=ns) == '13.0', 'Wrong minimum macOS'
    enclosure = item.find('enclosure')
    assert enclosure is not None
    expected = f'https://github.com/swlittles/Reclaim/releases/download/v{version}/Reclaim-{version}-macos-universal.dmg'
    assert enclosure.attrib['url'] == expected, 'Wrong asset URL'
    signature = enclosure.attrib['{' + ns['sparkle'] + '}edSignature']
    assert len(base64.b64decode(signature, validate=True)) == 64, 'Invalid Ed25519 signature encoding'
    assert int(enclosure.attrib['length']) == pathlib.Path(dmg).stat().st_size > 0, 'Enclosure does not match final file length'

if __name__ == '__main__':
    validate(*sys.argv[1:])
    print('Verified appcast version, build, minimum OS, signature encoding, exact asset URL and length.')
