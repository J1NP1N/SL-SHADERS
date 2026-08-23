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

$fnStart = $text.IndexOf("void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)")
if ($fnStart -lt 0) {
    throw "renderSSRBackgroundDepth() was not found. Nothing changed."
}

$fnEndMarker = "// Render all of our geometry that's required after our deferred pass."
$fnEnd = $text.IndexOf($fnEndMarker, $fnStart)
if ($fnEnd -lt 0) {
    throw "Could not find the end of renderSSRBackgroundDepth(). Nothing changed."
}

$fn = $text.Substring($fnStart, $fnEnd - $fnStart)

$startAnchor = "    target.bindTarget();"
$endAnchor = "    target.flush();"

$blockStart = $fn.IndexOf($startAnchor)
$blockEnd = $fn.IndexOf($endAnchor, $blockStart)

if ($blockStart -lt 0 -or $blockEnd -lt 0) {
    throw "Could not find the current background-depth draw block. Nothing changed."
}

$blockEnd += $endAnchor.Length

$currentBlock = $fn.Substring($blockStart, $blockEnd - $blockStart)

if ($currentBlock -match "SL SSR v0\.2\.4") {
    throw "The v0.2.4 camera-matrix fix already appears to be applied. Nothing changed."
}

$newBlock = @'
    // SL SSR v0.2.4: explicitly reload the main-camera matrices for the
    // depth-only shadow shader. Firestorm's normal renderShadow() path does
    // this before drawing; the original SSR auxiliary pass did not.
    const glm::mat4 ssr_camera_proj = get_current_projection();
    const glm::mat4 ssr_camera_view = get_current_modelview();

    target.bindTarget();

    {
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);

        GLdouble saved_depth_clear = 1.0;
        glGetDoublev(GL_DEPTH_CLEAR_VALUE, &saved_depth_clear);
        glClearDepth(1.0);
        target.clear(GL_DEPTH_BUFFER_BIT);
        glClearDepth(saved_depth_clear);

        LLGLEnable cull(GL_CULL_FACE);

        gGL.matrixMode(LLRender::MM_PROJECTION);
        gGL.pushMatrix();
        gGL.loadMatrix(glm::value_ptr(ssr_camera_proj));

        gGL.matrixMode(LLRender::MM_MODELVIEW);
        gGL.pushMatrix();
        gGL.loadMatrix(glm::value_ptr(ssr_camera_view));
        gGLLastMatrix = NULL;

        LLVertexBuffer::unbind();
        gGL.getTexUnit(0)->unbind(LLTexUnit::TT_TEXTURE);

        gDeferredShadowProgram.bind(false); // non-rigged only
        gGL.diffuseColor4f(1.f, 1.f, 1.f, 1.f);
        gGL.getTexUnit(0)->disable();

        for (U32 type : types)
        {
            renderObjects(type, false, false, false);
        }

        renderGLTFObjects(LLRenderPass::PASS_GLTF_PBR, false, false);

        gGL.getTexUnit(0)->enable(LLTexUnit::TT_TEXTURE);
        gDeferredShadowProgram.unbind();

        gGL.matrixMode(LLRender::MM_PROJECTION);
        gGL.popMatrix();
        gGL.matrixMode(LLRender::MM_MODELVIEW);
        gGL.popMatrix();
        gGLLastMatrix = NULL;
    }

    target.flush();
'@

$bak = "$p.slssr-bgdepth-v0.2.4.bak"
if (-not (Test-Path $bak)) {
    Copy-Item -LiteralPath $p -Destination $bak
}

$newFn = $fn.Substring(0, $blockStart) + $newBlock + $fn.Substring($blockEnd)
$newText = $text.Substring(0, $fnStart) + $newFn + $text.Substring($fnEnd)

[System.IO.File]::WriteAllText(
    $p,
    $newText,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Applied SL SSR background-depth v0.2.4 camera-matrix fix."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "Backup:"
Write-Host "  indra/newview/pipeline.cpp.slssr-bgdepth-v0.2.4.bak"
