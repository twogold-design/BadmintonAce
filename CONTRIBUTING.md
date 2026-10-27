# 协作开发

仓库包含可继续开发的 Godot 工程、完整新角色源文件、服务器源码、测试和发布脚本。build、dist、缓存、node_modules、EXE 与玩家数据库是生成或私人运行数据，不纳入版本管理。首次克隆后先导入 Godot 工程；源码根目录 index.html 需要先导出网页才能打开。

## 本地准备

使用 Godot 4.7.2、Node.js 24、Python 3。修改模型生成流程另需 Blender 4.4。Windows 示例（先将工具路径替换为自己的安装位置）：

```powershell
$env:GODOT_BIN='D:/tools/Godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$env:NODE_BIN='D:/tools/nodejs2/node.exe'
. ./tools/environment.ps1
npm --prefix server ci
npm --prefix tools ci
python -B tools/fetch_templates.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
```

Node/npm、Python 应在 PATH；浏览器测试默认 Chrome，可设置 ACE_BROWSER 为 Chrome/Edge 完整路径。模板、依赖缓存和临时文件均在项目目录。双击“打开Godot编辑器.cmd”，或运行 tools/editor.ps1 后按 F6/F5 调试。角色直接使用已提交 GLB，正常运行游戏无需先重建模型。

## 分工和提交

从 main 创建个人分支（建议 codex/简短任务名），小步提交，通过 Pull Request 合并。多人避免同时编辑 main.gd 或同一个 .blend；提前约定文件负责人。二进制模型无法逐行合并，应由一个人导出并连同生成脚本、骨骼 JSON 和来源许可一起提交。不要提交 .godot、.runtime、dist、密钥、数据库或个人 IP 配置的无关改动。

| 范围 | 文件 |
|---|---|
| 规则、UI、输入、AI | scripts/main.gd |
| 场地、镜头、3D 世界 | scripts/arena_3d.gd |
| 骨骼、握拍、击球、步伐 | scripts/athlete_3d.gd、footwork.gd |
| 模型及重建 | assets/athletes、tools/build_athletes.py |
| P2 显示缓冲 | scripts/remote_view.gd |
| 房间、密码、排行榜 | server |
| 构建、验证与浏览器操作 | tools |

## 验证与发布

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify.ps1 -Web
node tools/build_server.cjs
python -B tools/package_server.py
```

网页包由 build.ps1 生成；本地 index.html 所需的 local-data.js、local-loader.js 必须一起发。服务器 EXE 从服务器源码打包；不要覆盖正在运行的 EXE，先停止自己的测试服务。联机测试使用独立端口，不占用正式主机 8766。源码服务器可直接 node server/server.js。

网页与主机发布包都检查 200 MB 上限，比赛实际提交网页包。更新角色后检查正背面、引拍/触球/随挥以及浏览器中的男女角色，不能只看骨架测试结果。已有自动化只覆盖本机两个浏览器，正式比赛前仍需两台真实电脑测试网络、防火墙及性能。
