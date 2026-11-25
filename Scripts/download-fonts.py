"""Download the original WenKai fonts and verify their pinned SHA-256 hashes."""
import hashlib
import pathlib
import subprocess
import tempfile

folder = pathlib.Path(__file__).resolve().parent.parent / 'Resources/Fonts'
folder.mkdir(parents=True, exist_ok=True)
checksums = {
    'Regular': '2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b',
    'Medium': 'f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a',
}
for style, expected in checksums.items():
    destination = folder / f'LXGWWenKai-{style}.ttf'
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == expected:
        continue
    url = f'https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-{style}.ttf'
    with tempfile.TemporaryDirectory() as temporary:
        candidate = pathlib.Path(temporary) / destination.name
        subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--output', str(candidate), url], check=True)
        if hashlib.sha256(candidate.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'Font checksum mismatch: {destination.name}')
        destination.write_bytes(candidate.read_bytes())
    print(f'Verified {destination.name}')
