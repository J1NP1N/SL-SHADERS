param(
    [Parameter(Mandatory=$true)]
    [string]$FirestormRoot
)

$ErrorActionPreference = "Stop"

function Replace-Exact {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New,
        [string]$Label
    )

    $text = [System.IO.File]::ReadAllText($Path)
    $count = ([regex]::Matches($text, [regex]::Escape($Old))).Count
    if ($count -ne 1) {
        throw "$Label: expected exactly one anchor in $Path, found $count. No file was modified by this replacement."
    }

    $text = $text.Replace($Old, $New)
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "patched: $Label"
}

$root = (Resolve-Path $FirestormRoot).Path
$pipelineH = Join-Path $root "indra\newview\pipeline.h"
$pipelineCpp = Join-Path $root "indra\newview\pipeline.cpp"
$viewerDisplay = Join-Path $root "indra\newview\llviewerdisplay.cpp"

foreach ($p in @($pipelineH, $pipelineCpp, $viewerDisplay)) {
    if (-not (Test-Path $p)) { throw "Missing expected Firestorm source file: $p" }
}

if ((Select-String -Path $pipelineCpp -Pattern "SL_GetSSRBackgroundDepthInfo" -Quiet) -or
    (Select-String -Path $pipelineH -Pattern "ssrBackgroundDepth" -Quiet)) {
    throw "SL SSR background-depth patch already appears to be present. Nothing changed."
}

foreach ($p in @($pipelineH, $pipelineCpp, $viewerDisplay)) {
    $bak = "$p.slssr-bgdepth-v0.1.bak"
    if (-not (Test-Path $bak)) {
        Copy-Item -LiteralPath $p -Destination $bak
    }
}

Replace-Exact -Path $pipelineH -Label "pipeline public API" -Old @'
    void renderGeomDeferred(LLCamera& camera, bool do_occlusion = false);
    void renderGeomPostDeferred(LLCamera& camera);
    void renderGeomShadow(LLCamera& camera);
'@ -New @'
    void renderGeomDeferred(LLCamera& camera, bool do_occlusion = false);

    // SL SSR: camera-aligned static background depth for recovering geometry
    // hidden by rigged/avatar geometry in the primary deferred depth layer.
    void renderSSRBackgroundDepth(LLCamera& camera);
    U32 getSSRBackgroundDepthTexture() const;
    U32 getSSRBackgroundDepthWidth() const;
    U32 getSSRBackgroundDepthHeight() const;

    void renderGeomPostDeferred(LLCamera& camera);
    void renderGeomShadow(LLCamera& camera);
'@

Replace-Exact -Path $pipelineH -Label "render-target pack" -Old @'
        LLRenderTarget          screen;
        LLRenderTarget          deferredScreen;
        LLRenderTarget          deferredLight;

        //sun shadow map
'@ -New @'
        LLRenderTarget          screen;
        LLRenderTarget          deferredScreen;
        LLRenderTarget          deferredLight;

        // SL SSR: depth-only camera-space pass containing static opaque geometry.
        // Deliberately excludes rigged/avatar geometry in v0.1.
        LLRenderTarget          ssrBackgroundDepth;

        //sun shadow map
'@

Replace-Exact -Path $pipelineCpp -Label "native export bridge" -Old @'
bool    gDebugPipeline = false;
LLPipeline gPipeline;
const LLMatrix4* gGLLastMatrix = NULL;
'@ -New @'
bool    gDebugPipeline = false;
LLPipeline gPipeline;

// SL SSR background-depth v0.1.
// The target is allocated with the main screen buffers, but the extra geometry
// pass only runs while the ReShade bridge add-on has explicitly enabled it.
static bool gSLSSRBackgroundDepthEnabled = false;

U32 LLPipeline::getSSRBackgroundDepthTexture() const
{
    return mMainRT.ssrBackgroundDepth.getDepth();
}

U32 LLPipeline::getSSRBackgroundDepthWidth() const
{
    return mMainRT.ssrBackgroundDepth.getWidth();
}

U32 LLPipeline::getSSRBackgroundDepthHeight() const
{
    return mMainRT.ssrBackgroundDepth.getHeight();
}

#if LL_WINDOWS
#define SLSSR_NATIVE_EXPORT __declspec(dllexport)
#else
#define SLSSR_NATIVE_EXPORT
#endif

extern "C" SLSSR_NATIVE_EXPORT int SL_GetSSRBackgroundDepthInfo(
    unsigned int* texture,
    unsigned int* width,
    unsigned int* height)
{
    if (!texture || !width || !height)
    {
        return 0;
    }

    *texture = gPipeline.getSSRBackgroundDepthTexture();
    *width = gPipeline.getSSRBackgroundDepthWidth();
    *height = gPipeline.getSSRBackgroundDepthHeight();

    return (*texture != 0 && *width != 0 && *height != 0) ? 1 : 0;
}

extern "C" SLSSR_NATIVE_EXPORT void SL_SetSSRBackgroundDepthEnabled(int enabled)
{
    gSLSSRBackgroundDepthEnabled = enabled != 0;
}

#undef SLSSR_NATIVE_EXPORT

const LLMatrix4* gGLLastMatrix = NULL;
'@

Replace-Exact -Path $pipelineCpp -Label "background-depth allocation" -Old @'
    //allocate deferred rendering color buffers
    if (!mRT->deferredScreen.allocate(resX, resY, GL_RGBA, true)) return false;
    if (!addDeferredAttachments(mRT->deferredScreen)) return false;

    GLuint screenFormat = hdr ? GL_RGBA16F : GL_RGBA;
'@ -New @'
    //allocate deferred rendering color buffers
    if (!mRT->deferredScreen.allocate(resX, resY, GL_RGBA, true)) return false;
    if (!addDeferredAttachments(mRT->deferredScreen)) return false;

    // SL SSR: depth-only static-background target. A zero color format gives
    // LLRenderTarget an FBO with only its 24-bit depth texture, avoiding a
    // throwaway full-resolution color attachment.
    if (mRT == &mMainRT &&
        !mRT->ssrBackgroundDepth.allocate(resX, resY, 0, true))
    {
        return false;
    }

    GLuint screenFormat = hdr ? GL_RGBA16F : GL_RGBA;
'@

Replace-Exact -Path $pipelineCpp -Label "background-depth release" -Old @'
void LLPipeline::releaseScreenBuffers()
{
    mRT->screen.release();
    mRT->deferredScreen.release();
    mRT->deferredLight.release();
'@ -New @'
void LLPipeline::releaseScreenBuffers()
{
    mRT->screen.release();
    mRT->deferredScreen.release();
    mRT->deferredLight.release();
    mRT->ssrBackgroundDepth.release();
'@

$backgroundFunction = @'

// SL SSR background-depth v0.1.
//
// This is intentionally not a generic second-nearest depth peel yet. It reuses
// Firestorm's existing depth-only shadow program and the current main-camera
// draw lists, but renders only the non-rigged opaque material passes into a
// separate camera-aligned depth target. The immediate goal is to recover the
// static wall/floor depth hidden by an avatar in the primary deferred depth.
//
// Once this payload is proven in-world, the SSR tracer can treat it as a
// secondary layer when the primary sample is an occluder/miss.
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
    target.clear(GL_DEPTH_BUFFER_BIT);

    {
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);
        LLGLEnable cull(GL_CULL_FACE);

        LLVertexBuffer::unbind();
        gDeferredShadowProgram.bind(false);
        gGL.diffuseColor4f(1.f, 1.f, 1.f, 1.f);
        gGL.getTexUnit(0)->disable();

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

Replace-Exact -Path $pipelineCpp -Label "background-depth render pass" -Old @'
}

// Render all of our geometry that's required after our deferred pass.
// This is gonna be stuff like alpha, water, etc.
void LLPipeline::renderGeomPostDeferred(LLCamera& camera)
'@ -New @"
}
$backgroundFunction

// Render all of our geometry that's required after our deferred pass.
// This is gonna be stuff like alpha, water, etc.
void LLPipeline::renderGeomPostDeferred(LLCamera& camera)
"@

Replace-Exact -Path $viewerDisplay -Label "main deferred invocation" -Old @'
    gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance());

    gPipeline.mRT->deferredScreen.flush();

    gPipeline.renderDeferredLighting();
'@ -New @'
    gPipeline.renderGeomDeferred(*LLViewerCamera::getInstance());

    // SL SSR: fill the camera-aligned static background depth while the main
    // deferred draw lists and camera matrices are still current.
    gPipeline.renderSSRBackgroundDepth(*LLViewerCamera::getInstance());

    gPipeline.mRT->deferredScreen.flush();

    gPipeline.renderDeferredLighting();
'@

Write-Host ""
Write-Host "SL SSR background-depth v0.1 source patch applied."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.h"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host "  indra/newview/llviewerdisplay.cpp"
Write-Host ""
Write-Host "Backups use suffix: .slssr-bgdepth-v0.1.bak"
Write-Host "Rebuild Firestorm before installing/enabling the ReShade bridge."
