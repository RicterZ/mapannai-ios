#!/usr/bin/env python3
"""Download pinned official AMap distributions; no API keys are required."""
import pathlib, zipfile, tempfile, json, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
curl_options = ['--connect-timeout', '20', '--max-time', '180', '--retry', '3']
versions = {'AMap3DMap': '11.2.100', 'AMapFoundation': '1.9.1'}
for pod, version in versions.items():
    spec = json.loads(subprocess.check_output(['curl', '-fsSL', *curl_options, f'https://trunk.cocoapods.org/api/v1/pods/{pod}/specs/{version}']))
    with tempfile.TemporaryDirectory() as temporary:
        archive = pathlib.Path(temporary) / 'sdk.zip'
        subprocess.run(['curl', '-fSL', *curl_options, spec['source']['http'], '-o', str(archive)], check=True)
        with zipfile.ZipFile(archive) as package:
            package.extractall(root / 'Vendor')
    print(f'{pod} {version} downloaded')
