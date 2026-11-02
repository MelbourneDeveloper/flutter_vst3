"""Exercise generator string escaping, identifiers and factory syntax."""
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
    generated = {name: (path / 'generated' / name).read_text().replace('\r\n', '\n')
                 for name in ['echo_ids.h', 'metadata.cmake', 'echo_factory.cpp']}
    for line in ['kDelayTimeParam = 0,', 'kFeedbackParam = 1,', 'kMixParam = 2,', 'kBypassParam = 3,', 'kNumParameters = 4',
                 'kEchoProcessorUID(0x57ABC4DA, 0x33FD9739, 0x12DE22A0, 0xF021DB27);',
                 'kEchoControllerUID(0x09D1ACE6, 0xD8F32B8B, 0x0AA8F5F4, 0x6EA3EC61);']:
        assert line in generated['echo_ids.h'], line
    for line in ['set(JSON_PLUGIN_NAME "Echo")', 'set(JSON_BUNDLE_ID "com.cf.echo")', 'set(PARAM_COUNT "4")',
                 'set(JSON_FLUTTER_ENTRYPOINT "echoMain")']:
        assert line in generated['metadata.cmake'], line
    for line in ['"Echo",', '"Echo Controller",', '"Fx|Delay",', '"1.0.0",']:
        assert line in generated['echo_factory.cpp'], line
    print('PASS exact escaping, identifiers, rejection, SDK syntax and unchanged Echo identifiers, UIDs and factory')
