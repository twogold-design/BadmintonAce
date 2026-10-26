"""Download only the web template from the official release archive."""
import io, os, struct, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'

class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        req = urllib.request.Request(url, method='HEAD')
        with urllib.request.urlopen(req, timeout=60) as r:
            self.url = r.url
            self.size = int(r.headers['Content-Length'])
        self.pos = 0
        print('Archive size:', self.size, flush=True)
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos + offset if whence == 1 else self.size + offset
        return self.pos
    def read(self, count=-1):
        if count < 0: count = self.size - self.pos
        if not count: return b''
        req = urllib.request.Request(self.url, headers={'Range': f'bytes={self.pos}-{self.pos+count-1}'})
        with urllib.request.urlopen(req, timeout=180) as r:
            if r.status != 206: raise RuntimeError('Server did not honor range request')
            data = r.read()
        self.pos += len(data)
        return data

dest = ROOT / '.runtime' / 'roaming' / 'Godot' / 'export_templates' / '4.7.2.stable'
dest.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(RemoteZip(URL)) as z:
    names = [n for n in z.namelist() if 'web' in n and 'nothreads' in n and 'release' in n]
    if not names:
        print(z.namelist(), flush=True)
        raise RuntimeError('No compatible template')
    for name in names:
        target = dest / Path(name).name
        print('Downloading', name, flush=True)
        target.write_bytes(z.read(name))
        print('Saved', target, target.stat().st_size, flush=True)
