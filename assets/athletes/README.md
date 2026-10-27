# 3D 运动员源文件

运行时使用 male.glb、female.glb 与对应 *-rig.json。男女保留原始完整人体骨架，女生额外有 ponytail 骨骼。清爽马尾网格、发圈、运动鞋、运动服着色和羽毛球程序动作在本工程制作。身体与运动服共享连续拓扑及蒙皮权重，不使用旧版分段拼接人体。

基础人体、面部纹理、原始绑定、头皮和短发来自 Quaternius Universal Base Characters，CC0-1.0。官方页面：https://quaternius.com/packs/universalbasecharacters.html 。免费 Standard 资源的来源镜像及下载文件哈希记录在 source/provenance.json，许可原文见 source/base-license.txt。本项目没有使用付费 Pro/Source 包或其他游戏的角色。

source/male.blend 与 source/female.blend 为可编辑项目；隐藏的 EditableFullBody 保留全身网格。source/base、source/hair、source/textures 是本地完整输入，不依赖下载地址长期有效。source/.gdignore 防止源文件进入网页包。

## 重建

从项目根目录运行 tools/environment.ps1 后，将 BLENDER_USER_CONFIG、BLENDER_USER_SCRIPTS 指向项目 .runtime 下的文件夹，再运行 Blender 4.4：

```powershell
$env:BLENDER_USER_CONFIG="$PWD/.runtime/blender/config"
$env:BLENDER_USER_SCRIPTS="$PWD/.runtime/blender/scripts"
& $env:BLENDER_BIN --background --factory-startup --python-exit-code 1 --python tools/build_athletes.py
```

BLENDER_BIN 设置为自己的 Blender 可执行文件。此命令会重建并覆盖两个 .blend、.glb 和骨骼测量 JSON；手工编辑 .blend 前请提交到自己的分支，手工造型不应直接被生成脚本覆盖。改生成规则时修改 tools/build_athletes.py；手工修改模型时同步导出 GLB 并保持原始骨骼命名、米制尺度和朝向（游戏里面向 -Z）。

scripts/athlete_3d.gd 从实际骨骼尺寸计算动作。不要再把人体拉伸到旧角色尺寸。scripts/athlete_materials.gd 和 athlete_kit.gdshader 使用 UV2 的休止态 X/高度定义球衣、短裤、袜口边界。握拍约定：右手指向、拇指侧与掌面在文件内注释，拇指侧必须朝拍头；肘部使用共享弯曲平面。

检查：tools/test_3d.gd 测试男女/P1/P2、接触位置、原始骨段长度、落脚、握拍方向与实际球拍变换；tools/capture_3d.gd 与 tools/motion_preview.gd 生成真实渲染预览。
