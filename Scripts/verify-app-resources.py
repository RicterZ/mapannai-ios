#!/usr/bin/env python3
"""Verify the SDK resource bundle in a built app before device installation."""
import hashlib
import sys
from pathlib import Path

source = Path(__file__).resolve().parent.parent / 'Vendor/MAMapKit.framework/AMap.bundle'
app = Path(sys.argv[1])
destination = app / 'AMap.bundle'
for required in ('localization.bundle', 'AMap3D.bundle'):
    if not (destination / required).is_dir():
        raise SystemExit(f'Missing SDK resource bundle: {required}')
files = [p for p in source.rglob('*') if p.is_file()]
if not files:
    raise SystemExit('SDK resources not downloaded')
for file in files:
    relative = file.relative_to(source)
    copied = destination / relative
    if not copied.is_file() or hashlib.sha256(file.read_bytes()).digest() != hashlib.sha256(copied.read_bytes()).digest():
        raise SystemExit(f'Missing or mismatched SDK resource: {relative}')
print(f'Verified {len(files)} SDK resource files')
