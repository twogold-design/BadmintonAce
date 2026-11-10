# 场边观众

由本工程 `assets/athletes/male.glb`、`female.glb` 简化得到，人物和材质来源、许可沿用 `assets/athletes/ATHLETE-LICENSE.txt`。座椅为本项目自建。没有引入额外人物资产。

`male.res`、`female.res` 为共享的轻量静态网格；`*-poses.res` 存储六组顶点位置和法线：坐姿观看、略前倾观看、坐姿鼓掌张手/合手、站姿鼓掌张手/合手。运行时由 GPU 在这些经过骨骼求解的姿势之间插值。座椅与脚掌保持落地，前后帧共用拓扑。

`*-flag.res` 和 `*-horn.res` 及对应姿势纹理为持小旗/小喇叭版本。道具几何由 `tools/crowd_props_source.gd` 自建，并与手部一起烘焙；持道具者使用持握、举旗、举喇叭动作，空手放在腿侧，不做双手鼓掌。总人数不增加，其中 16 人拿旗、8 人拿喇叭。观众与座椅使用第 2 渲染层，只接收较暗的看台灯光；球场主灯使用第 1 层。

重建：先运行项目导入，然后用 Godot 执行 `--headless --path . --script tools/bake_crowd.gd`。简化、颜色采样与骨骼索引转换在 `tools/crowd_mesh_source.gd`，姿势与座椅在 `tools/bake_crowd.gd`。无需 Blender。普通游戏启动不需要执行重建。

验证：`tools/test_crowd.gd` 检查预算、姿势、比赛状态与暂停；使用原生渲染器运行可额外验证实例位置。`tools/capture_crowd.gd` 生成实际镜头截图；`node tools/check_crowd.cjs` 验证网页版动画和暂停。
