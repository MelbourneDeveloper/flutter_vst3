"""Exercise generator string escaping, identifiers and factory syntax."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
sdk = Path(os.environ['VST3_SDK_DIR'])
assert (sdk / 'pluginterfaces/base/funknown.h').is_file()
metadata = json.loads((root / 'vsts/echo/plugin_metadata.json').read_text())
with tempfile.TemporaryDirectory(prefix='generator-strings-') as tmp:
    path = Path(tmp)
    metadata['pluginName'] = 'Space "Echo" \\ 音'
    metadata['parameters'][0]['name'] = 'wet-dry'
    (path / 'plugin_metadata.json').write_text(json.dumps(metadata))
    command = ['dart', str(root / 'flutter_vst3/scripts/generate_plugin.dart'), str(path), 'echo', 'echo', str(path)]
    subprocess.run(command, check=True)
    factory = (path / 'generated/echo_factory.cpp').read_text()
    assert '"Space \\"Echo\\" \\\\ 音"' in factory, factory
    assert 'kWetDryParam = 0,' in (path / 'generated/echo_ids.h').read_text()
    assert 'set(JSON_PLUGIN_NAME "Space \\"Echo\\" \\\\ 音")' in (path / 'generated/metadata.cmake').read_text()
    for source in ['echo_factory.cpp', 'echo_controller.cpp', 'echo_processor.cpp']:
        subprocess.run(['g++', '-std=c++17', '-DNDEBUG', '-fsyntax-only', '-I' + str(sdk), '-I' + str(root / 'flutter_vst3/native/include'), str(path / 'generated' / source)], check=True)
    for names, error in [(['wet-dry', 'wet_dry'], 'Metadata error: duplicate parameter identifier WetDry'), ([''], 'Metadata error: unusable identifier: '), (['音'], 'Metadata error: unusable identifier: 音')]:
        for param, name in zip(metadata['parameters'], names):
            param['name'] = name
        (path / 'plugin_metadata.json').write_text(json.dumps(metadata))
        result = subprocess.run(command, text=True, capture_output=True)
        assert result.returncode == 1, result.stdout
        assert result.stdout.splitlines()[-1] == 'CRITICAL ERROR: FormatException: ' + error, result.stdout
    metadata = json.loads((root / 'vsts/echo/plugin_metadata.json').read_text())
    (path / 'plugin_metadata.json').write_text(json.dumps(metadata))
    subprocess.run(command, check=True)
    expected = {
        'echo_factory.cpp': '52881c5f83a609aa1a1b7d562507affbf9536fb35136ea3bd7aad940cf1fd91e',
        'echo_ids.h': '0c92cf336a4e984f869c04ca020b44fb1f495b8d80f43d87036af96534ba3be5',
        'metadata.cmake': '530ae649f994ae6c4f6cef46556fb97759aaa72b6267f6117605eeeabb67e240',
    }
    for name, digest in expected.items():
        assert hashlib.sha256((path / 'generated' / name).read_bytes()).hexdigest() == digest, name
    print('PASS exact escaping, identifiers, rejection, SDK syntax and byte-identical Echo identifiers, UIDs and factory')
