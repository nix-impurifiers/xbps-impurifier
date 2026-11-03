# SPDX-License-Identifier: MIT
"""Compile immutable native-owned object trees into genuine XBPS packages."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

collection, destination = map(Path, sys.argv[1:3])
architecture = sys.argv[3]
destination.mkdir()
for package in json.loads((collection / 'packages.json').read_text()):
    record = json.loads((collection / package / 'metadata.json').read_text())
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+~]*', record['version']):
        raise ValueError('unsupported native XBPS version: ' + record['version'])
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary) / 'root'
        shutil.copytree(collection / package / 'tree', root, symlinks=True)
        command = ['xbps-create', '-A', architecture, '-n', record['name'] + '-' + record['version'] + '_1',
                   '-s', 'Native-owned Nix-built payload', '-l', 'LicenseRef-Unknown']
        if record['dependencies']:
            command += ['-D', ' '.join(name + '-1_1' for name in record['dependencies'])]
        subprocess.run(command + [str(root)], cwd=destination, check=True)
