# SPDX-License-Identifier: MIT
"""Generate an xbps-src recipe from actual binary-package metadata."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys

artifact, options, output = map(Path, sys.argv[1:])
source = json.loads(options.read_text())["sourceUrl"]
metadata = plistlib.loads(subprocess.check_output(["bsdtar", "-xOf", str(artifact), "./props.plist"]))
name = metadata["pkgname"]
version, revision = metadata["version"].rsplit("_", 1)
if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", name) or not re.fullmatch(r"[0-9]+", revision):
    raise ValueError("invalid native package identity")
output.mkdir(parents=True)
lines = ["# SPDX-License-Identifier: MIT", "# Generated impurifier payload recipe; application compilation remains in Nix."]
for key, value in [
    ("pkgname", name), ("version", version), ("revision", revision),
    ("short_desc", metadata["short_desc"]), ("license", metadata["license"]),
    ("homepage", "https://github.com/nix-impurifiers/xbps-impurifier"),
    ("maintainer", "Impurifier package publisher"),
    ("archs", "*" if metadata["architecture"] == "noarch" else metadata["architecture"]),
    ("distfiles", source + ">impurifier.xbps"),
    ("checksum", hashlib.file_digest(artifact.open("rb"), "sha256").hexdigest()),
    ("skip_extraction", "impurifier.xbps"), ("create_wrksrc", "yes"),
    ("nostrip", "yes"), ("noshlibprovides", "yes"), ("noverifyrdeps", "yes"),
]:
    lines.append(key + "=" + shlex.quote(value))
for key, native in [("depends", "run_depends"), ("provides", "provides"), ("conflicts", "conflicts"), ("replaces", "replaces"), ("conf_files", "conf_files")]:
    if metadata.get(native):
        lines.append(key + "=" + shlex.quote(" ".join(metadata[native])))
# Retain native lifecycle scripts as recipe inputs. xbps-src wraps these using
# its own metadata-script generator; no fake callback or replacement builder.
entries = subprocess.check_output(["bsdtar", "-tf", str(artifact)], text=True).splitlines()
for script in ["INSTALL", "REMOVE"]:
    entry = next((e for e in entries if e.removeprefix("./") == script), None)
    if entry:
        (output / script).write_bytes(subprocess.check_output(["bsdtar", "-xOf", str(artifact), entry]))
lines += [
    "do_install() {",
    '  bsdtar --no-same-owner -xf "$XBPS_SRCDISTDIR/$pkgname-$version/impurifier.xbps" -C "$DESTDIR"',
    '  rm -f "$DESTDIR/props.plist" "$DESTDIR/files.plist" "$DESTDIR/INSTALL" "$DESTDIR/REMOVE"',
    "}",
]
(output / "template").write_text("\n".join(lines) + "\n")
