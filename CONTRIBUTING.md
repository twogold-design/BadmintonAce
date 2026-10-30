# 协作开发

仓库包含 Godot 工程、完整角色源文件、服务器源码、测试、发布脚本，以及可直接运行的 `build/web/` 网页版本。其余 build 输出、dist、缓存、node_modules、EXE 与玩家数据库不纳入版本管理。

## 首次拉取后怎样运行

**先试玩：直接打开仓库根目录的 `index.html`，点击“单机游玩”。** git clone 或 Code → Download ZIP 完整解压后即可运行，不用安装 Godot、Node.js 或自行导出。入口会自动加载随仓库提供的 `build/web/`，请保留该目录全部文件。单机不需要服务器；登录、排行榜和局域网对战需要可访问的游戏服务器。

**修改和调试源码：** 用 Godot 4.7.2 导入根目录 `project.godot`，等待资源导入完成，按 F5。角色 GLB、纹理、字体和脚本均已提交，常规游戏开发不需要 Blender。

Windows 上建议设置 `GODOT_BIN` 后双击“打开Godot编辑器.cmd”，缓存与用户数据会保存在工程的 `.runtime` 中。工具路径按自己的电脑设置，不要求与原开发者的盘符一致。

修改源码不会自动改变已导出的网页。需要在浏览器检查自己的修改时，完成下方构建环境准备，运行 `重新导出网页版.cmd`。提交可试玩版本时，将源码和更新后的 `build/web/` 一起提交，保证同伴拉取后打开 `index.html` 看到的是新版本。入口若显示缺少网页文件，检查是否仅下载了 HTML、使用了稀疏检出，或尚未拉取包含网页资源的最新提交。

“开始游戏.cmd”用于带服务器 EXE 的完整发布包。源码协作者也可安装服务端依赖后运行 `node server/server.js` 测试联机。试玩玩家可以使用完整仓库副本或独立的 `dist/BadmintonAce-Web.zip`。

## 本地准备

以下是网页构建和完整测试的环境；仅用 Godot 调试可跳过。使用 Godot 4.7.2、Node.js 24、Python 3。修改模型生成流程另需 Blender 4.4。Windows 示例（先将工具路径替换为自己的安装位置）：

```powershell
$env:GODOT_BIN='D:/tools/Godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$env:NODE_BIN='D:/tools/nodejs2/node.exe'
. ./tools/environment.ps1
npm --prefix server ci
npm --prefix tools ci
python -B tools/fetch_templates.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
```

Node/npm、Python 应在 PATH；浏览器测试默认 Chrome，可设置 ACE_BROWSER 为 Chrome/Edge 完整路径。模板、依赖缓存和临时文件均在项目目录。网页导出模板必须与 Godot 版本一致，并放到 `.runtime/roaming/Godot/export_templates/4.7.2.stable/`；`fetch_templates.py` 会自动下载至此处。若下载失败，也可把官方模板包中的 `web_nothreads_release.zip` 手动解压到该目录（保留 ZIP 文件本身）。系统用户目录里已安装的模板不会自动用于此工程。

## 分工和提交

从 main 创建个人分支（建议 codex/简短任务名），小步提交，通过 Pull Request 合并。多人避免同时编辑 main.gd 或同一个 .blend；提前约定文件负责人。二进制模型无法逐行合并，应由一个人导出并连同生成脚本、骨骼 JSON 和来源许可一起提交。提交可试玩版本时包含 build/web；不要提交其他构建输出、.godot、.runtime、dist、密钥、数据库或个人 IP 配置的无关改动。

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
node tools/check_checkout_entry.cjs
node tools/check_server_access.cjs --browser
node tools/build_server.cjs
python -B tools/package_server.py
python -B tools/package_cloud.py
```

网页包由 build.ps1 生成；本地 index.html 所需的 local-data.js、local-loader.js 必须一起发。服务器 EXE 从服务器源码打包；不要覆盖正在运行的 EXE，先停止自己的测试服务。联机测试使用独立端口，不占用正式主机 8766。源码服务器可直接 node server/server.js。

网页与主机发布包都检查 200 MB 上限，比赛实际提交网页包。更新角色后检查正背面、引拍/触球/随挥以及浏览器中的男女角色，不能只看骨架测试结果。已有自动化只覆盖本机两个浏览器，正式比赛前仍需两台真实电脑测试网络、防火墙及性能。

`tools/check_checkout_entry.cjs` 从 Git 暂存区复制完整的已跟踪文件到隔离目录，再用浏览器从本地文件入口进行单机回合测试；运行前先暂存准备提交的网页与源码。测试不借用工作区里的未跟踪导出文件，也不需要服务器。

云端验证：设置 OPENSSL_BIN 后运行 `node tools/check_cloud_backend.cjs`，验证本地完整游戏包通过 HTTPS 反向代理/WSS 对战；后台不提供游戏资源，测试禁用 WebRTC。此项使用隔离数据库和端口，不等于真实公网部署验收。
