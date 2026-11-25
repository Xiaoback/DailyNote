import json
import pathlib
import sys

original = sys.argv[1]
build = pathlib.Path(sys.argv[2])
overlay = {'version': 0, 'roots': [{
    'type': 'file', 'name': original,
    'external-contents': str(build / 'empty.modulemap'),
}]}
(build / 'toolchain-overlay.json').write_text(json.dumps(overlay), encoding='utf-8')
