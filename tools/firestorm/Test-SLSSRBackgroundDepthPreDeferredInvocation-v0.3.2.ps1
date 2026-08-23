param(
    [Parameter(Mandatory=$true)]
    [string]$FirestormRoot
)

$ErrorActionPreference = "Stop"

$p = Join-Path $FirestormRoot "indra\newview\llviewerdisplay.cpp"
if (-not (Test-Path $p)) {
    throw "Missing llviewerdisplay.cpp: $p"
}

$text = [System.IO.File]::ReadAllText($p)

# Require the current diagnostic build so we do not relocate an unrelated call.
$pipeline = Join-Path $FirestormRoot "indra\newview\pipeline.cpp"
if (-not (Test-Path $pipeline)) {
    throw "Missing pipeline.cpp: $pipeline"
}
$pipelineText = [System.IO.File]::ReadAllText($pipeline)
if ($pipelineText -notmatch "SL SSR TEST C3 RENDER MAP COUNTS") {
    throw "Expected TEST C3 render-map instrumentation is not active. Nothing changed."
}

$call = "gPipeline.renderSSRBackgroundDepth(*LLViewerCamera::getInstance());"

$count = ([regex]::Matches($text, [regex]::Escape($call))).Count
if ($count -lt 1) {
    throw "Could not find the existing renderSSRBackgroundDepth() invocation. Nothing changed."
}

# Remove every existing invocation first. Previous builds placed it after the
# deferred geometry pass; that is too late because the LLCullResult render maps
# have already been emptied.
$text = $text.Replace("            $call`r`n", "")
$text = $text.Replace("            $call`n", "")
$text = $text.Replace("$call`r`n", "")
$text = $text.Replace("$call`n", "")

$needleCRLF = "            gGL.setColorMask(true, true);`r`n            gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance(), true);"
$needleLF   = "            gGL.setColorMask(true, true);`n            gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance(), true);"

$replacementCRLF = "            gGL.setColorMask(true, true);`r`n            // SL SSR TEST C4: run while the world render maps are still populated.`r`n            $call`r`n            gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance(), true);"
$replacementLF   = "            gGL.setColorMask(true, true);`n            // SL SSR TEST C4: run while the world render maps are still populated.`n            $call`n            gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance(), true);"

if ($text.Contains($needleCRLF)) {
    $text = $text.Replace($needleCRLF, $replacementCRLF)
}
elseif ($text.Contains($needleLF)) {
    $text = $text.Replace($needleLF, $replacementLF)
}
else {
    throw "Could not find the main-world renderGeomDeferred(..., true) anchor. Nothing changed."
}

$newCount = ([regex]::Matches($text, [regex]::Escape($call))).Count
if ($newCount -ne 1) {
    throw "Expected exactly one relocated invocation, found $newCount. Nothing written."
}

$bak = "$p.slssr-bgdepth-testC4-predeferred-invocation.bak"
if (-not (Test-Path $bak)) {
    Copy-Item -LiteralPath $p -Destination $bak
}

[System.IO.File]::WriteAllText(
    $p,
    $text,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Applied SL SSR TEST C4: moved background-depth pass before main deferred geometry."
Write-Host "Modified:"
Write-Host "  indra/newview/llviewerdisplay.cpp"
Write-Host ""
Write-Host "C3 instrumentation remains active."
Write-Host "After rebuild/run, search Firestorm.log for:"
Write-Host "  SLSSR_BGDEPTH_C3"
Write-Host ""
Write-Host "Expected change:"
Write-Host "  one or more MAP entries have drawinfos > 0"
Write-Host "  RESULT changed_pixels > 0 and min < 1"
