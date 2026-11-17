#!/usr/bin/env python3
"""Keep the former ArticulationBox ReaPack URL compatible with ReaScripts."""
import argparse
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET

SOURCE = 'https://raw.githubusercontent.com/andreynovikov86-cmd/ReaScripts/main/index.xml'
REPOSITORY = 'https://github.com/andreynovikov86-cmd/ReaScripts/tree/main/ArticulationBox'


def compatibility_index(source: str, current: str) -> str:
    root = ET.fromstring(source)
    previous = ET.fromstring(current)
    assert root.tag == 'index' and root.get('version') == '1', 'Invalid source index'
    assert previous.tag == 'index', 'Invalid compatibility index'
    categories = root.findall("category[@name='ArticulationBox']")
    assert len(categories) == 1, 'Expected one ArticulationBox category'
    packages = categories[0].findall('reapack')
    assert len(packages) == 1 and packages[0].get('name') == 'Articulation_Manager.lua', 'Unexpected package identity'
    versions = packages[0].findall('version')
    assert versions and len({v.get('name') for v in versions}) == len(versions), 'Missing or duplicate releases'
    # Never drop a release already offered to existing installations.
    history = previous.find("category[@name='ArticulationBox']/reapack")
    if history is not None:
        available = {v.get('name') for v in versions}
        assert all(v.get('name') in available for v in history.findall('version')), 'Source removed a historical version'
    blocks = re.findall(r'  <category name="ArticulationBox">[\s\S]*?  </category>', source)
    assert len(blocks) == 1, 'Cannot isolate the package category'
    # Keep the former repository name, category, package and installed file names.
    # Download links and release metadata come verbatim from the shared index.
    result = ('<?xml version="1.0" encoding="utf-8"?>\n'
              '<index version="1" name="Andrey Novikov">\n' + blocks[0] + '\n'
              '  <metadata>\n'
              '    <description>{\\rtf1\\ansi ArticulationBox is maintained in ReaScripts by Andrey Novikov. This compatibility index mirrors its releases so existing installations can keep updating.}</description>\n'
              f'    <link href="{REPOSITORY}">Current package</link>\n'
              f'    <link href="{SOURCE}">Shared ReaPack index</link>\n'
              '  </metadata>\n</index>\n')
    assert ET.fromstring(result).find('category/reapack').get('name') == 'Articulation_Manager.lua'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-file', type=Path, help='Use an already downloaded shared index for validation')
    parser.add_argument('--output', type=Path, default=Path('index.xml'))
    args = parser.parse_args()
    if args.source_file:
        source = args.source_file.read_text(encoding='utf-8')
    else:
        request = urllib.request.Request(SOURCE, headers={'User-Agent': 'ArticulationBox-ReaPack-compatibility'})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(4 * 1024 * 1024 + 1)
        assert len(data) <= 4 * 1024 * 1024, 'Source index is too large'
        source = data.decode('utf-8')
    result = compatibility_index(source, args.output.read_text(encoding='utf-8'))
    temporary = args.output.with_suffix('.xml.tmp')
    temporary.write_text(result, encoding='utf-8')
    temporary.replace(args.output)
    print('Compatibility index matches the ArticulationBox releases in ReaScripts.')


if __name__ == '__main__':
    main()
