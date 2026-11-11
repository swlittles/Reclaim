import os, pathlib, subprocess, unittest

class ReleaseTests(unittest.TestCase):
    def test_production_requires_own_key(self):
        env = dict(os.environ, RECLAIM_BUILD_VARIANT='production', RECLAIM_SPARKLE_PUBLIC_KEY_FILE='/nonexistent/reclaim-key')
        p = subprocess.run(['bash', 'scripts/build.sh'], env=env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('real Reclaim Ed25519 public key', p.stderr)
    def test_unknown_variant_is_rejected(self):
        p = subprocess.run(['bash', 'scripts/build.sh'], env=dict(os.environ, RECLAIM_BUILD_VARIANT='typo'), capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
    def test_stable_has_no_unsigned_fallback(self):
        p = subprocess.run(['bash', 'scripts/release.sh', 'signed'], env={k:v for k,v in os.environ.items() if k not in ['RECLAIM_SIGNING_IDENTITY','NOTARY_PROFILE']}, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('Developer ID', p.stderr)
    def test_tag_must_match_version(self):
        p = subprocess.run(['python3', 'scripts/validate-version.py'], env=dict(os.environ, RELEASE_TAG='v999.0.0'), capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)

class AppcastTests(unittest.TestCase):
    def test_exact_final_enclosure_is_required(self):
        import base64, importlib.util, tempfile
        spec = importlib.util.spec_from_file_location('appcast', 'scripts/validate-appcast.py')
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        with tempfile.TemporaryDirectory() as directory:
            dmg = pathlib.Path(directory, 'Reclaim-0.1.0-macos-universal.dmg'); dmg.write_bytes(b'fixture')
            xml = pathlib.Path(directory, 'appcast.xml')
            signature = base64.b64encode(bytes(64)).decode()
            text = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>1</sparkle:version><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString><sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion><enclosure url="https://github.com/swlittles/Reclaim/releases/download/v0.1.0/Reclaim-0.1.0-macos-universal.dmg" length="7" sparkle:edSignature="{signature}"/></item></channel></rss>'''
            xml.write_text(text); mod.validate(xml, '0.1.0', 1, dmg)
            for broken in [text.replace('length="7"', 'length="8"'), text.replace('>1<', '>2<'), text.replace('/v0.1.0/', '/v0.0.1/'), text.replace('>13.0<', '>14.0<')]:
                xml.write_text(broken)
                with self.assertRaises(AssertionError): mod.validate(xml, '0.1.0', 1, dmg)
