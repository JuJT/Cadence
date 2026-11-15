#!/usr/bin/env python3
"""Prepare explicit ad-hoc metadata for later re-signing, without any Apple identity."""
import plistlib
import sys
from pathlib import Path

TEMPLATE_PREFIX = 'UNSIGNED00.'


def prepare(source):
    values = plistlib.loads(source)
    groups = values.get('keychain-access-groups')
    if groups is not None:
        values['keychain-access-groups'] = [item.replace('$(AppIdentifierPrefix)', TEMPLATE_PREFIX) for item in groups]
    return values


if __name__ == '__main__':
    source, destination = map(Path, sys.argv[1:])
    destination.write_bytes(plistlib.dumps(prepare(source.read_bytes())))
