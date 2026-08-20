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

$misplaced = @'
    gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance());

    // SL SSR: fill the camera-aligned static background depth while the main
    // deferred draw lists and camera matrices are still current.
    gPipeline.renderSSRBackgroundDepth(*LLViewerCamera::getInstance());

    gPipeline.mRT->deferredScreen.flush();
'@

$fixedCube = @'
    gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance());

    gPipeline.mRT->deferredScreen.flush();
'@

$mainOld = @'
            gGL.setColorMask(true, true);
            gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance(), true);
        }
'@

$mainNew = @'
            gGL.setColorMask(true, true);
            gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance(), true);

            // SL SSR v0.2.7: run the auxiliary background-depth pass in the
            // actual main world render, not display_cube_face().
            gPipeline.renderSSRBackgroundDepth(*LLViewerCamera::getInstance());
        }
'@

$misplacedCount = ([regex]::Matches($text, [regex]::Escape($misplaced))).Count
$mainCount = ([regex]::Matches($text, [regex]::Escape($mainOld))).Count

if ($misplacedCount -ne 1) {
    throw "Expected exactly one misplaced display_cube_face SSR invocation, found $misplacedCount. Nothing changed."
}
if ($mainCount -ne 1) {
    throw "Expected exactly one main world render anchor, found $mainCount. Nothing changed."
}

$bak = "$p.slssr-bgdepth-v0.2.7-invocation.bak"
if (-not (Test-Path $bak)) {
    Copy-Item -LiteralPath $p -Destination $bak
}

$text = $text.Replace($misplaced, $fixedCube)
$text = $text.Replace($mainOld, $mainNew)

[System.IO.File]::WriteAllText(
    $p,
    $text,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Applied SL SSR v0.2.7 main-render invocation fix."
Write-Host "Modified:"
Write-Host "  indra/newview/llviewerdisplay.cpp"
Write-Host ""
Write-Host "Moved renderSSRBackgroundDepth():"
Write-Host "  FROM display_cube_face()"
Write-Host "  TO   the main world deferred render"
Write-Host ""
Write-Host "Keep TEST A2 active for the next run."
