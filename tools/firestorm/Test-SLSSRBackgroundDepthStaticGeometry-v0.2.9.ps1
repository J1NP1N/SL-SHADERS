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

if ($oldFn -notmatch "SL SSR TEST B CONSTANT DEPTH") {
    throw "Expected TEST B constant-depth function is not active. Nothing changed."
}
if ($oldFn -match "SL SSR TEST C STATIC GEOMETRY") {
    throw "TEST C static-geometry patch already appears to be applied. Nothing changed."
}

$newFn = @'
void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)
{
    LL_PROFILE_ZONE_SCOPED_CATEGORY_DRAWPOOL;
    LL_PROFILE_GPU_ZONE("renderSSRBackgroundDepth");

    (void)camera;

    // SL SSR TEST C STATIC GEOMETRY
    //
    // Render the nearest non-rigged/static opaque depth from the main camera
    // into the auxiliary depth target. This is Dstatic, not a generic
    // second-nearest depth peel.

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

    static const U32 types[] = {
        LLRenderPass::PASS_SIMPLE,
        LLRenderPass::PASS_FULLBRIGHT,
        LLRenderPass::PASS_SHINY,
        LLRenderPass::PASS_BUMP,
        LLRenderPass::PASS_FULLBRIGHT_SHINY,
        LLRenderPass::PASS_MATERIAL,
        LLRenderPass::PASS_MATERIAL_ALPHA_EMISSIVE,
        LLRenderPass::PASS_SPECMAP,
        LLRenderPass::PASS_SPECMAP_EMISSIVE,
        LLRenderPass::PASS_NORMMAP,
        LLRenderPass::PASS_NORMMAP_EMISSIVE,
        LLRenderPass::PASS_NORMSPEC,
        LLRenderPass::PASS_NORMSPEC_EMISSIVE
    };

    const bool saved_shadow_render = sShadowRender;
    const U32 saved_occlusion = sUseOcclusion;

    sShadowRender = true;
    sUseOcclusion = 0;

    target.bindTarget();

    {
        // Establish writable depth state before clearing the depth-only FBO.
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);

        GLdouble saved_depth_clear = 1.0;
        glGetDoublev(GL_DEPTH_CLEAR_VALUE, &saved_depth_clear);
        glClearDepth(1.0);
        target.clear(GL_DEPTH_BUFFER_BIT);
        glClearDepth(saved_depth_clear);

        LLGLEnable cull(GL_CULL_FACE);

        LLVertexBuffer::unbind();

        // Non-rigged depth-only shadow program.
        gDeferredShadowProgram.bind(false);
        gGL.diffuseColor4f(1.f, 1.f, 1.f, 1.f);
        gGL.getTexUnit(0)->unbind(LLTexUnit::TT_TEXTURE);

        for (U32 type : types)
        {
            renderObjects(type, false, false, false);
        }

        renderGLTFObjects(LLRenderPass::PASS_GLTF_PBR, false, false);

        gDeferredShadowProgram.unbind();
    }

    target.flush();

    sUseOcclusion = saved_occlusion;
    sShadowRender = saved_shadow_render;
}

'@

$bak = "$p.slssr-bgdepth-testC-static-geometry.bak"
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
Write-Host "Applied SL SSR TEST C: static/non-rigged geometry depth."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "Expected after rebuild/run:"
Write-Host "  Background NATIVE RAW shows world geometry."
Write-Host "  Avatar/rigged silhouette is absent from that depth layer."
Write-Host "  Wall/floor depth remains visible through the avatar silhouette."
