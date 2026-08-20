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

$oldFn = $text.Substring($fnStart, $fnEnd - $fnStart)

if ($oldFn -match "SL SSR TEST A CLEAR ONLY") {
    throw "Test A clear-only patch already appears to be applied. Nothing changed."
}

$newFn = @'
void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)
{
    LL_PROFILE_ZONE_SCOPED_CATEGORY_DRAWPOOL;
    LL_PROFILE_GPU_ZONE("renderSSRBackgroundDepth");

    (void)camera;

    if (!gSLSSRBackgroundDepthEnabled ||
        mRT != &mMainRT ||
        gCubeSnapshot ||
        sReflectionRender ||
        sImpostorRender)
    {
        return;
    }

    LLRenderTarget& target = mMainRT.ssrBackgroundDepth;
    if (!target.isComplete())
    {
        return;
    }

    // SL SSR TEST A CLEAR ONLY
    //
    // Diagnostic purpose:
    // Prove the auxiliary depth target -> exported GL texture ->
    // ReShade bridge -> FX sampler path before drawing any geometry.
    //
    // Expected Background NATIVE RAW result: solid white (depth = 1.0).
    target.bindTarget();

    {
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);

        GLdouble saved_depth_clear = 1.0;
        glGetDoublev(GL_DEPTH_CLEAR_VALUE, &saved_depth_clear);

        glClearDepth(1.0);
        target.clear(GL_DEPTH_BUFFER_BIT);

        glClearDepth(saved_depth_clear);
    }

    target.flush();
}

'@

$bak = "$p.slssr-bgdepth-testA-clearonly.bak"
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
Write-Host "Applied SL SSR TEST A: clear-only background depth."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "Expected after rebuild:"
Write-Host "  Link / native pair: CYAN"
Write-Host "  Primary NATIVE RAW: normal scene depth"
Write-Host "  Background NATIVE RAW: SOLID WHITE"
