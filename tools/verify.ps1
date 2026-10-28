param([switch]$Web)
. (Join-Path $PSScriptRoot 'environment.ps1')
$godot = Resolve-AceTool 'GODOT_BIN' @('godot','godot4') 'D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --path $projectRoot --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
foreach ($test in @('test_login','test_round_head','test_backhand','test_rescue_step','test_forefoot','test_service_stance','test_arm_followthrough','test_rear_serve','test_stroke_balance','test_three_keys','test_locomotion','test_demo','test_3d','test_motion','test_controls','test_mechanics','test_shot_variation')) {
    & $godot --headless --path $projectRoot --script "tools/$test.gd"
    if ($LASTEXITCODE -ne 0) { throw "$test failed" }
}
if ($Web) {
    $node = Resolve-AceTool 'NODE_BIN' @('node') 'D:\tools\nodejs2\node.exe'
    & $node 'tools/test_release.cjs'
    if ($LASTEXITCODE -ne 0) { throw 'Release and multiplayer checks failed' }
}
