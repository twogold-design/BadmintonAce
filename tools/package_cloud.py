from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
dest = root / 'dist' / 'BadmintonAce-Cloud.zip'
dest.parent.mkdir(exist_ok=True)
files = [root / name for name in ['Dockerfile', '.dockerignore', 'compose.yaml', 'assets/challenges.json', 'docs/部署与邀请.md']]
files += [p for p in (root / 'server').iterdir() if p.is_file() and p.name != '.gdignore' and not p.name.startswith('test')]
files += [root / 'deploy' / name for name in ['Caddyfile', '.env.example']]
with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in files:
        z.write(p, p.relative_to(root).as_posix())
with zipfile.ZipFile(dest) as check:
    assert not any(n.startswith(('build/', 'data/')) or n.endswith(('.exe', '.sqlite', '.pem', '.key')) for n in check.namelist())
print(f'Backend-only cloud package: {dest.stat().st_size / 1000:.1f} KB; no game assets, executable or player database.')
