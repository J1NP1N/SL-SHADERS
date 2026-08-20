param(
    [Parameter(Mandatory=$true)]
    [string]$FirestormRoot
)

$ErrorActionPreference = "Stop"

$p = Join-Path $FirestormRoot "indra\newview\pipeline.cpp"
if (-not (Test-Path $p)) {
    throw "Missing pipeline.cpp: $p"
}

$text = [System.IO.File]::ReadAllText($p)

$fnStartText = "void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)"
$fnStart = $text.IndexOf($fnStartText)
if ($fnStart -lt 0) {
    throw "renderSSRBackgroundDepth() was not found. Nothing changed."
}

$fnEndMarker = "// Render all of our geometry that's required after our deferred pass."
$fnEnd = $text.IndexOf($fnEndMarker, $fnStart)
if ($fnEnd -lt 0) {
    throw "Could not find the end of renderSSRBackgroundDepth(). Nothing changed."
}

$fn = $text.Substring($fnStart, $fnEnd - $fnStart)

if ($fn -notmatch "SL SSR TEST A2 NATIVE READBACK") {
    throw "Expected TEST A2 native-readback function is not active. Nothing changed."
}
if ($fn -match "SL SSR TEST B CONSTANT DEPTH") {
    throw "TEST B constant-depth patch already appears to be applied. Nothing changed."
}

$oldClear = "        glClearDepth(1.0);`r`n        target.clear(GL_DEPTH_BUFFER_BIT);"
$newClear = "        glClearDepth(0.5);`r`n        target.clear(GL_DEPTH_BUFFER_BIT);"

if (-not $fn.Contains($oldClear)) {
    $oldClear = "        glClearDepth(1.0);`n        target.clear(GL_DEPTH_BUFFER_BIT);"
    $newClear = "        glClearDepth(0.5);`n        target.clear(GL_DEPTH_BUFFER_BIT);"
}
if (-not $fn.Contains($oldClear)) {
    throw "Could not find the TEST A2 depth clear. Nothing changed."
}

$newFn = $fn.Replace("SL SSR TEST A2 NATIVE READBACK", "SL SSR TEST B CONSTANT DEPTH")
$newFn = $newFn.Replace("SLSSR_BGDEPTH_A2", "SLSSR_BGDEPTH_B")
$newFn = $newFn.Replace(
    "// Keep this pass clear-only, but instrument the native Firestorm side.",
    "// Controlled constant-depth test: clear the auxiliary target to raw depth 0.5."
)
$newFn = $newFn.Replace($oldClear, $newClear)

$bak = "$p.slssr-bgdepth-testB-constant-depth.bak"
if (-not (Test-Path $bak)) {
    Copy-Item -LiteralPath $p -Destination $bak
}

$newText = $text.Substring(0, $fnStart) + $newFn + $text.Substring($fnEnd)

[System.IO.File]::WriteAllText(
    $p,
    $newText,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Applied SL SSR TEST B: constant raw depth 0.5."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "Expected after rebuild/run:"
Write-Host "  Firestorm log center=0.5 corner=0.5"
Write-Host "  Background NATIVE RAW = uniform 50% gray"
