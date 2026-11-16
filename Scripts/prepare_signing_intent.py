#!/usr/bin/env python3
"""Prepare explicit ad-hoc metadata for later re-signing, without any Apple identity."""
import plistlib
import argparse
from pathlib import Path

TEMPLATE_PREFIX = 'UNSIGNED00.'


def prepare(source, bundle_identifier=None):
    values = plistlib.loads(source)
    groups = values.get('keychain-access-groups')
    if groups is not None:
        resolved = []
        for item in groups:
            if '$(PRODUCT_BUNDLE_IDENTIFIER)' in item:
                if not bundle_identifier or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-' for c in bundle_identifier):
                    raise ValueError('Un identifiant de bundle compilé est requis pour le groupe privé.')
                item = item.replace('$(PRODUCT_BUNDLE_IDENTIFIER)', bundle_identifier)
            resolved.append(item.replace('$(AppIdentifierPrefix)', TEMPLATE_PREFIX))
        values['keychain-access-groups'] = resolved
    return values


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--bundle-info', type=Path)
    args = parser.parse_args()
    bundle_identifier = None
    if args.bundle_info:
        bundle_identifier = plistlib.loads(args.bundle_info.read_bytes())['CFBundleIdentifier']
    args.destination.write_bytes(plistlib.dumps(prepare(args.source.read_bytes(), bundle_identifier)))
