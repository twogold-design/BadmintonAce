from pathlib import Path
import zipfile
import os

root = Path(__file__).resolve().parents[1]
dest = root / 'dist' / 'BadmintonAce-Server.zip'
with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for folder in ['server', 'build/web']:
        for p in sorted((root / folder).rglob('*')):
            if p.is_file() and p.name != '.gdignore':
                z.write(p, p.relative_to(root).as_posix())
    z.write(root / 'README.md', 'README.md')
    z.write(root / 'assets/challenges.json', 'assets/challenges.json')
    for name in ['docs/动作参考与实现.md','artifacts/motion-reference-sheet.png']:
        if (root / name).exists():
            z.write(root / name, name)
    for name in ['Dockerfile','.dockerignore','docs/部署与邀请.md','docs/局域网使用说明.md','docs/GM管理.md','docs/NODE-LICENSE.txt','tools/play.ps1','tools/gm.ps1','GM管理.cmd','tools/allow_lan.ps1','允许局域网联机.cmd','开始游戏.cmd','BadmintonAce-Server.exe','index.html']:
        source = Path(os.environ['ACE_SERVER_EXE']) if name == 'BadmintonAce-Server.exe' and os.environ.get('ACE_SERVER_EXE') else root / name
        if source.exists():
            z.write(source, name)
with zipfile.ZipFile(dest) as check:
    total=sum(item.file_size for item in check.infolist())
    assert total < 200_000_000, f'Server package extracted size exceeds limit: {total}'
assert dest.stat().st_size < 200_000_000
print(f'Extracted server package: {total / 1000000:.2f} MB')
print(f'Deployment package: {dest.stat().st_size / 1000000:.2f} MB')
