param(
    [Parameter(Mandatory=$true)]
    [string]$FirestormRoot
)

$ErrorActionPreference = "Stop"

$pipelineCpp = Join-Path $FirestormRoot "indra\newview\pipeline.cpp"
$pipelineH   = Join-Path $FirestormRoot "indra\newview\pipeline.h"
$shaderDir   = Join-Path $FirestormRoot "indra\newview\app_settings\shaders\class1\deferred"
$shadowAlpha = Join-Path $shaderDir "shadowAlphaMaskF.glsl"
$pbrAlpha    = Join-Path $shaderDir "pbrShadowAlphaMaskF.glsl"
$treeShadow  = Join-Path $shaderDir "treeShadowF.glsl"

foreach ($p in @($pipelineCpp, $pipelineH, $shadowAlpha, $pbrAlpha, $treeShadow)) {
    if (-not (Test-Path $p)) {
        throw "Missing expected Firestorm source file: $p"
    }
}

$ct = [System.IO.File]::ReadAllText($pipelineCpp)
$ht = [System.IO.File]::ReadAllText($pipelineH)
$sa = [System.IO.File]::ReadAllText($shadowAlpha)
$pa = [System.IO.File]::ReadAllText($pbrAlpha)
$ts = [System.IO.File]::ReadAllText($treeShadow)

function Get-FunctionSpan([string]$text, [int]$signatureStart) {
    $brace = $text.IndexOf("{", $signatureStart)
    if ($brace -lt 0) { throw "Could not find function opening brace." }

    $depth = 0
    for ($i = $brace; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($ch -eq '{') {
            $depth++
        }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return @{ Start = $signatureStart; End = $i + 1 }
            }
        }
    }

    throw "Could not find function closing brace."
}

function Replace-One(
    [string]$text,
    [string]$pattern,
    [string]$replacement,
    [string]$label)
{
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $label anchor; found $($matches.Count). Nothing written."
    }

    $m = $matches[0]
    return $text.Substring(0, $m.Index) + $replacement +
           $text.Substring($m.Index + $m.Length)
}

# ---------------------------------------------------------------------------
# Baseline / idempotence gates.
# ---------------------------------------------------------------------------

if ($ct -notmatch 'SL_GetSSRAvatarBackDepthInfo') {
    throw "Expected validated v0.49 DavatarBack export SL_GetSSRAvatarBackDepthInfo. Nothing written."
}
if ($ct -notmatch 'SLSSR_AVBACK_COVERAGE_V0491') {
    throw "Expected Fix-SLSSRAvatarBackDepthCoverage-v0.49.1 baseline marker. Nothing written."
}
if ($ht -notmatch 'ssrAvatarBackDepth') {
    throw "Expected validated ssrAvatarBackDepth target in pipeline.h. Nothing written."
}
if ($ct -match 'SL_NATIVE_ALPHA_CAPTURE_V01' -or
    $ct -match 'SL_GetAlphaMaterialInfo' -or
    $ht -match 'ssrAlphaMaterial') {
    throw "SL native alpha geometry v0.1 already appears to be applied. Nothing written."
}

foreach ($shader in @(
    @{ Name = "shadowAlphaMaskF.glsl"; Text = $sa },
    @{ Name = "pbrShadowAlphaMaskF.glsl"; Text = $pa },
    @{ Name = "treeShadowF.glsl"; Text = $ts }
)) {
    if ($shader.Text -match 'sl_alpha_capture_output') {
        throw "$($shader.Name) already contains sl_alpha_capture_output. Nothing written."
    }
}

# ---------------------------------------------------------------------------
# pipeline.h
# ---------------------------------------------------------------------------

$rtPattern = '(?m)^(?<indent>[ \t]*)LLRenderTarget[ \t]+ssrAvatarBackDepth;[ \t]*$'
$rtMatch = [regex]::Match($ht, $rtPattern)
if (-not $rtMatch.Success) {
    throw "Could not find ssrAvatarBackDepth declaration in pipeline.h."
}
$rtIndent = $rtMatch.Groups["indent"].Value
$rtReplacement = $rtMatch.Value + "`r`n" +
    $rtIndent + "// SL native alpha geometry v0.1: private nearest alpha/cutout captures.`r`n" +
    $rtIndent + "LLRenderTarget          ssrAlphaMaterial;`r`n" +
    $rtIndent + "LLRenderTarget          ssrAlphaCoverage;"
$ht2 = Replace-One $ht $rtPattern $rtReplacement "ssrAvatarBackDepth declaration"

$getterDeclPattern = '(?m)^(?<indent>[ \t]*)U32[ \t]+getSSRAvatarBackDepthHeight\(\)[ \t]+const;[ \t]*$'
$getterDeclMatch = [regex]::Match($ht2, $getterDeclPattern)
if (-not $getterDeclMatch.Success) {
    throw "Could not find getSSRAvatarBackDepthHeight() declaration."
}
$gdIndent = $getterDeclMatch.Groups["indent"].Value
$getterDeclReplacement = $getterDeclMatch.Value + "`r`n`r`n" +
    $gdIndent + "// SL native alpha geometry v0.1.`r`n" +
    $gdIndent + "U32 getAlphaMaterialTexture() const;`r`n" +
    $gdIndent + "U32 getAlphaDepthTexture() const;`r`n" +
    $gdIndent + "U32 getAlphaCoverageTexture() const;`r`n" +
    $gdIndent + "U32 getAlphaGeometryWidth() const;`r`n" +
    $gdIndent + "U32 getAlphaGeometryHeight() const;"
$ht2 = Replace-One $ht2 $getterDeclPattern $getterDeclReplacement "avatar-back getter declaration"

$renderAlphaDeclPattern = '(?m)^(?<indent>[ \t]*)void[ \t]+renderAlphaObjects\(bool rigged = false\);[ \t]*$'
$renderAlphaDeclMatch = [regex]::Match($ht2, $renderAlphaDeclPattern)
if (-not $renderAlphaDeclMatch.Success) {
    throw "Could not find renderAlphaObjects(bool rigged = false) declaration."
}
$raIndent = $renderAlphaDeclMatch.Groups["indent"].Value
$renderAlphaDeclReplacement =
    $raIndent + "void renderAlphaObjects(bool rigged = false, F32 minimum_alpha = -1.f, S32 alpha_capture_output = 0);"
$ht2 = Replace-One $ht2 $renderAlphaDeclPattern $renderAlphaDeclReplacement "renderAlphaObjects declaration"

# ---------------------------------------------------------------------------
# pipeline.cpp globals and renderAlphaObjects capture controls.
# ---------------------------------------------------------------------------

$pipelineGlobalPattern = '(?m)^LLPipeline gPipeline;[ \t]*$'
$pipelineGlobalReplacement = @'
LLPipeline gPipeline;

// SL native alpha geometry v0.1. Armed by the ReShade bridge.
static bool gSLAlphaGeometryEnabled = false;
'@.TrimEnd("`r", "`n")
$ct2 = Replace-One $ct $pipelineGlobalPattern $pipelineGlobalReplacement "LLPipeline gPipeline"

$hashedPattern = '(?m)^static LLStaticHashedString sScreenRes\("screenRes"\);[ \t]*$'
$hashedReplacement = @'
static LLStaticHashedString sScreenRes("screenRes");
static LLStaticHashedString sSLAlphaCaptureOutput("sl_alpha_capture_output");
'@.TrimEnd("`r", "`n")
$ct2 = Replace-One $ct2 $hashedPattern $hashedReplacement "sScreenRes hashed uniform"

$renderAlphaSig = "void LLPipeline::renderAlphaObjects(bool rigged)"
$renderAlphaPos = $ct2.IndexOf($renderAlphaSig)
if ($renderAlphaPos -lt 0) {
    throw "Could not find renderAlphaObjects(bool rigged) definition."
}
$renderAlphaSpan = Get-FunctionSpan $ct2 $renderAlphaPos
$renderAlphaBlock = $ct2.Substring(
    $renderAlphaSpan.Start,
    $renderAlphaSpan.End - $renderAlphaSpan.Start)

$renderAlphaBlock2 = $renderAlphaBlock.Replace(
    $renderAlphaSig,
    "void LLPipeline::renderAlphaObjects(bool rigged, F32 minimum_alpha, S32 alpha_capture_output)"
)

$assertNeedle = "    assertInitialized();"
$assertCount = ([regex]::Matches($renderAlphaBlock2, [regex]::Escape($assertNeedle))).Count
if ($assertCount -ne 1) {
    throw "Expected exactly one assertInitialized() in renderAlphaObjects(); found $assertCount."
}
$renderAlphaBlock2 = $renderAlphaBlock2.Replace(
    $assertNeedle,
    $assertNeedle + @'

    const F32 sl_alpha_minimum =
        minimum_alpha >= 0.f ? minimum_alpha : ALPHA_BLEND_CUTOFF;
'@
)

$oldCutoff = "LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(ALPHA_BLEND_CUTOFF);"
$cutoffCount = ([regex]::Matches(
    $renderAlphaBlock2,
    [regex]::Escape($oldCutoff))).Count
if ($cutoffCount -lt 1) {
    throw "Expected shadow alpha cutoff writes inside renderAlphaObjects(); found none."
}
$newCutoff = @'
LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(sl_alpha_minimum);
                LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                    sSLAlphaCaptureOutput, alpha_capture_output);
'@.TrimEnd("`r", "`n")
$renderAlphaBlock2 = $renderAlphaBlock2.Replace($oldCutoff, $newCutoff)

$ct2 = $ct2.Substring(0, $renderAlphaSpan.Start) +
       $renderAlphaBlock2 +
       $ct2.Substring($renderAlphaSpan.End)

# ---------------------------------------------------------------------------
# Native target allocation/release.
# ---------------------------------------------------------------------------

$avatarAllocPattern = '(?s)if \(mRT == &mMainRT &&\s*!mRT->ssrAvatarBackDepth\.allocate\(resX,\s*resY,\s*0,\s*true\)\)\s*\{\s*return false;\s*\}'
$avatarAllocMatch = [regex]::Match($ct2, $avatarAllocPattern)
if (-not $avatarAllocMatch.Success) {
    throw "Could not find validated ssrAvatarBackDepth allocation block."
}
$alphaAlloc = $avatarAllocMatch.Value + @'

    // SL native alpha geometry v0.1. RGBA16F + depth so color and nearest
    // alpha geometry depth are produced by the same private raster pass.
    if (mRT == &mMainRT &&
        !mRT->ssrAlphaMaterial.allocate(resX, resY, GL_RGBA16F, true))
    {
        return false;
    }

    if (mRT == &mMainRT &&
        !mRT->ssrAlphaCoverage.allocate(resX, resY, GL_RGBA16F, true))
    {
        return false;
    }
'@
$ct2 = Replace-One $ct2 $avatarAllocPattern $alphaAlloc "ssrAvatarBackDepth allocation"

$avatarReleasePattern = '(?m)^(?<indent>[ \t]*)mRT->ssrAvatarBackDepth\.release\(\);[ \t]*$'
$avatarReleaseMatch = [regex]::Match($ct2, $avatarReleasePattern)
if (-not $avatarReleaseMatch.Success) {
    throw "Could not find ssrAvatarBackDepth.release()."
}
$relIndent = $avatarReleaseMatch.Groups["indent"].Value
$releaseReplacement = $avatarReleaseMatch.Value + "`r`n" +
    $relIndent + "mRT->ssrAlphaMaterial.release();`r`n" +
    $relIndent + "mRT->ssrAlphaCoverage.release();"
$ct2 = Replace-One $ct2 $avatarReleasePattern $releaseReplacement "ssrAvatarBackDepth release"

# ---------------------------------------------------------------------------
# Getter definitions.
# ---------------------------------------------------------------------------

$avatarGetterSig = "U32 LLPipeline::getSSRAvatarBackDepthHeight() const"
$avatarGetterPos = $ct2.IndexOf($avatarGetterSig)
if ($avatarGetterPos -lt 0) {
    throw "Could not find $avatarGetterSig."
}
$avatarGetterSpan = Get-FunctionSpan $ct2 $avatarGetterPos
$avatarGetterBlock = $ct2.Substring(
    $avatarGetterSpan.Start,
    $avatarGetterSpan.End - $avatarGetterSpan.Start)

$alphaGetterBlock = $avatarGetterBlock + @'

U32 LLPipeline::getAlphaMaterialTexture() const
{
    return mMainRT.ssrAlphaMaterial.getTexture(0);
}

U32 LLPipeline::getAlphaDepthTexture() const
{
    return mMainRT.ssrAlphaMaterial.getDepth();
}

U32 LLPipeline::getAlphaCoverageTexture() const
{
    return mMainRT.ssrAlphaCoverage.getTexture(0);
}

U32 LLPipeline::getAlphaGeometryWidth() const
{
    return mMainRT.ssrAlphaMaterial.getWidth();
}

U32 LLPipeline::getAlphaGeometryHeight() const
{
    return mMainRT.ssrAlphaMaterial.getHeight();
}
'@
$ct2 = $ct2.Substring(0, $avatarGetterSpan.Start) +
       $alphaGetterBlock +
       $ct2.Substring($avatarGetterSpan.End)

# ---------------------------------------------------------------------------
# C ABI exports.
# ---------------------------------------------------------------------------

$avatarExportSig = 'extern "C" SLSSR_NATIVE_EXPORT int SL_GetSSRAvatarBackDepthInfo'
$avatarExportPos = $ct2.IndexOf($avatarExportSig)
if ($avatarExportPos -lt 0) {
    throw "Could not find SL_GetSSRAvatarBackDepthInfo export."
}
$avatarExportLineStart = $ct2.LastIndexOf("`n", $avatarExportPos)
if ($avatarExportLineStart -lt 0) {
    $avatarExportLineStart = 0
}
else {
    $avatarExportLineStart++
}
$avatarExportSpan = Get-FunctionSpan $ct2 $avatarExportLineStart

$alphaExports = @'

extern "C" SLSSR_NATIVE_EXPORT void SL_SetAlphaGeometryEnabled(int enabled)
{
    gSLAlphaGeometryEnabled = enabled != 0;
}

extern "C" SLSSR_NATIVE_EXPORT int SL_GetAlphaMaterialInfo(
    unsigned int* texture,
    unsigned int* width,
    unsigned int* height)
{
    if (!texture || !width || !height)
    {
        return 0;
    }

    *texture = gPipeline.getAlphaMaterialTexture();
    *width = gPipeline.getAlphaGeometryWidth();
    *height = gPipeline.getAlphaGeometryHeight();

    return (*texture != 0 && *width != 0 && *height != 0) ? 1 : 0;
}

extern "C" SLSSR_NATIVE_EXPORT int SL_GetAlphaDepthInfo(
    unsigned int* texture,
    unsigned int* width,
    unsigned int* height)
{
    if (!texture || !width || !height)
    {
        return 0;
    }

    *texture = gPipeline.getAlphaDepthTexture();
    *width = gPipeline.getAlphaGeometryWidth();
    *height = gPipeline.getAlphaGeometryHeight();

    return (*texture != 0 && *width != 0 && *height != 0) ? 1 : 0;
}

extern "C" SLSSR_NATIVE_EXPORT int SL_GetAlphaCoverageInfo(
    unsigned int* texture,
    unsigned int* width,
    unsigned int* height)
{
    if (!texture || !width || !height)
    {
        return 0;
    }

    *texture = gPipeline.getAlphaCoverageTexture();
    *width = gPipeline.getAlphaGeometryWidth();
    *height = gPipeline.getAlphaGeometryHeight();

    return (*texture != 0 && *width != 0 && *height != 0) ? 1 : 0;
}
'@

$ct2 = $ct2.Substring(0, $avatarExportSpan.End) +
       $alphaExports +
       $ct2.Substring($avatarExportSpan.End)

# ---------------------------------------------------------------------------
# Main pre-deferred native capture.
# ---------------------------------------------------------------------------

$renderSig = "void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)"
$renderPos = $ct2.IndexOf($renderSig)
if ($renderPos -lt 0) {
    throw "Could not find renderSSRBackgroundDepth()."
}
$renderSpan = Get-FunctionSpan $ct2 $renderPos
$renderBlock = $ct2.Substring(
    $renderSpan.Start,
    $renderSpan.End - $renderSpan.Start)

$oldGuard = "    if (!gSLSSRBackgroundDepthEnabled ||"
$guardCount = ([regex]::Matches(
    $renderBlock,
    [regex]::Escape($oldGuard))).Count
if ($guardCount -ne 1) {
    throw "Expected exactly one SSR enabled guard in renderSSRBackgroundDepth(); found $guardCount."
}
$renderBlock2 = $renderBlock.Replace(
    $oldGuard,
    "    if ((!gSLSSRBackgroundDepthEnabled && !gSLAlphaGeometryEnabled) ||"
)

$restoreAnchor = @'
    gGL.setColorMask(true, true);
    sUseOcclusion = saved_occlusion;
    sShadowRender = saved_shadow_render;
'@
$restoreCount = ([regex]::Matches(
    $renderBlock2,
    [regex]::Escape($restoreAnchor))).Count
if ($restoreCount -ne 1) {
    throw "Expected exactly one final native state-restore anchor; found $restoreCount."
}

$alphaCapture = @'
    // ---------------------------------------------------------------------
    // SL_NATIVE_ALPHA_CAPTURE_V01
    //
    // Geometry semantic capture only. No framebuffer-alpha inference.
    // Explicit pass replay excludes sky/WL sky/cloud render paths. A temporary
    // render-type mask additionally removes particles and HUD alpha from the
    // shared alpha-group helper.
    //
    // Two identical depth-writing replays are deliberate for v0.1:
    //   ssrAlphaMaterial:  R=1 for eligible alpha geometry + nearest depth
    //   ssrAlphaCoverage: R=authored blend alpha / 1 for surviving cutouts
    //
    // This keeps SL_ALPHA_MATERIAL, SL_DEPTH_ALPHA_NATIVE and
    // SL_ALPHA_COVERAGE tied to the same nearest eligible fragment without
    // adding MRT plumbing to the Firestorm shader manager.
    // ---------------------------------------------------------------------
    if (gSLAlphaGeometryEnabled)
    {
        pushRenderTypeMask();
        clearRenderTypeMask(
            RENDER_TYPE_SKY,
            RENDER_TYPE_WL_SKY,
            RENDER_TYPE_CLOUDS,
            RENDER_TYPE_PARTICLES,
            RENDER_TYPE_HUD,
            RENDER_TYPE_HUD_PARTICLES,
            END_RENDER_TYPES);

        const S32 sl_alpha_sun_up =
            LLEnvironment::instance().getIsSunUp() ? 1 : 0;

        const auto sl_alpha_capture_target =
            [&](LLRenderTarget& alpha_target, bool coverage_pass)
        {
            if (!alpha_target.isComplete() ||
                alpha_target.getNumTextures() == 0)
            {
                return;
            }

            alpha_target.bindTarget();

            GLfloat sl_saved_color_clear[4] = { 0.f, 0.f, 0.f, 0.f };
            GLdouble sl_saved_depth_clear = 1.0;
            glGetFloatv(GL_COLOR_CLEAR_VALUE, sl_saved_color_clear);
            glGetDoublev(GL_DEPTH_CLEAR_VALUE, &sl_saved_depth_clear);

            glClearColor(0.f, 0.f, 0.f, 0.f);
            glClearDepth(1.0);
            alpha_target.clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

            glClearColor(
                sl_saved_color_clear[0],
                sl_saved_color_clear[1],
                sl_saved_color_clear[2],
                sl_saved_color_clear[3]);
            glClearDepth(sl_saved_depth_clear);

            const S32 sl_mask_output = coverage_pass ? 3 : 1;
            const S32 sl_blend_output = coverage_pass ? 2 : 1;
            const U32 sl_target_width = LLRenderTarget::sCurResX;

            {
                LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);
                LLGLDisable blend(GL_BLEND);
                LLGLEnable cull(GL_CULL_FACE);

                for (S32 sl_rigged_index = 0;
                     sl_rigged_index < 2;
                     ++sl_rigged_index)
                {
                    const bool sl_rigged = sl_rigged_index != 0;

                    // Legacy alpha-mask geometry.
                    gDeferredShadowAlphaMaskProgram.bind(sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        LLShaderMgr::SUN_UP_FACTOR, sl_alpha_sun_up);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1f(
                        LLShaderMgr::DEFERRED_SHADOW_TARGET_WIDTH,
                        static_cast<float>(sl_target_width));
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, sl_mask_output);
                    renderMaskedObjects(
                        LLRenderPass::PASS_ALPHA_MASK,
                        true,
                        true,
                        sl_rigged);
                    gDeferredShadowAlphaMaskProgram.unbind();

                    // True blended alpha. Capture threshold is intentionally
                    // far below Firestorm's 0.598 shadow cutoff.
                    renderAlphaObjects(
                        sl_rigged,
                        0.004f,
                        sl_blend_output);

                    // Fullbright cutout geometry.
                    gDeferredShadowFullbrightAlphaMaskProgram.bind(sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        LLShaderMgr::SUN_UP_FACTOR, sl_alpha_sun_up);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1f(
                        LLShaderMgr::DEFERRED_SHADOW_TARGET_WIDTH,
                        static_cast<float>(sl_target_width));
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, sl_mask_output);
                    renderFullbrightMaskedObjects(
                        LLRenderPass::PASS_FULLBRIGHT_ALPHA_MASK,
                        true,
                        true,
                        sl_rigged);
                    gDeferredShadowFullbrightAlphaMaskProgram.unbind();

                    // Legacy material alpha-mask variants.
                    gDeferredTreeShadowProgram.bind(sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, sl_mask_output);
                    renderMaskedObjects(
                        LLRenderPass::PASS_NORMSPEC_MASK,
                        true, false, sl_rigged);
                    renderMaskedObjects(
                        LLRenderPass::PASS_MATERIAL_ALPHA_MASK,
                        true, false, sl_rigged);
                    renderMaskedObjects(
                        LLRenderPass::PASS_SPECMAP_MASK,
                        true, false, sl_rigged);
                    renderMaskedObjects(
                        LLRenderPass::PASS_NORMMAP_MASK,
                        true, false, sl_rigged);
                    gDeferredTreeShadowProgram.unbind();

                    // GLTF alpha-mask geometry.
                    gDeferredShadowGLTFAlphaMaskProgram.bind(sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        LLShaderMgr::SUN_UP_FACTOR, sl_alpha_sun_up);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1f(
                        LLShaderMgr::DEFERRED_SHADOW_TARGET_WIDTH,
                        static_cast<float>(sl_target_width));
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, sl_mask_output);

                    gGL.loadMatrix(gGLModelView);
                    gGLLastMatrix = NULL;

                    if (sl_rigged)
                    {
                        mAlphaMaskPool->pushRiggedGLTFBatches(
                            LLRenderPass::PASS_GLTF_PBR_ALPHA_MASK_RIGGED);
                    }
                    else
                    {
                        mAlphaMaskPool->pushGLTFBatches(
                            LLRenderPass::PASS_GLTF_PBR_ALPHA_MASK);
                    }

                    gGL.loadMatrix(gGLModelView);
                    gGLLastMatrix = NULL;
                    gDeferredShadowGLTFAlphaMaskProgram.unbind();
                }

                // Grass is an alpha-tested cutout path outside PASS_ALPHA_MASK.
                gDeferredTreeShadowProgram.bind(false);
                LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(0.5f);
                LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                    sSLAlphaCaptureOutput, sl_mask_output);
                renderObjects(LLRenderPass::PASS_GRASS, true);
                gDeferredTreeShadowProgram.unbind();

                // Linden system trees are a dedicated texture-keyed cutout pool.
                for (const auto& sl_tree_entry : mTreePools)
                {
                    LLDrawPool* sl_tree_pool = sl_tree_entry.second;
                    if (!sl_tree_pool)
                    {
                        continue;
                    }

                    sl_tree_pool->beginShadowPass(0);
                    gDeferredTreeShadowProgram.uniform1i(
                        sSLAlphaCaptureOutput, sl_mask_output);
                    sl_tree_pool->renderShadow(0);
                    sl_tree_pool->endShadowPass(0);
                }
            }

            alpha_target.flush();
        };

        sl_alpha_capture_target(mMainRT.ssrAlphaMaterial, false);
        sl_alpha_capture_target(mMainRT.ssrAlphaCoverage, true);

        popRenderTypeMask();
    }

    gGL.setColorMask(true, true);
    sUseOcclusion = saved_occlusion;
    sShadowRender = saved_shadow_render;
'@

$renderBlock2 = $renderBlock2.Replace($restoreAnchor, $alphaCapture)
$ct2 = $ct2.Substring(0, $renderSpan.Start) +
       $renderBlock2 +
       $ct2.Substring($renderSpan.End)

# ---------------------------------------------------------------------------
# Shader capture-output mode.
# ---------------------------------------------------------------------------

function Patch-ShaderMain(
    [string]$text,
    [string]$name,
    [string]$newMain)
{
    $uniformPattern = '(?m)^uniform float minimum_alpha;[ \t]*$'
    $uniformMatches = [regex]::Matches($text, $uniformPattern)
    if ($uniformMatches.Count -ne 1) {
        throw "Expected exactly one minimum_alpha uniform in $name; found $($uniformMatches.Count)."
    }

    $text2 = Replace-One $text $uniformPattern (
        $uniformMatches[0].Value +
        "`r`nuniform int sl_alpha_capture_output;"
    ) "$name minimum_alpha uniform"

    $mainSig = "void main()"
    $mainPos = $text2.IndexOf($mainSig)
    if ($mainPos -lt 0) {
        throw "Could not find void main() in $name."
    }

    $mainSpan = Get-FunctionSpan $text2 $mainPos
    return $text2.Substring(0, $mainSpan.Start) +
           $newMain.TrimEnd("`r", "`n") +
           $text2.Substring($mainSpan.End)
}

$shadowAlphaMain = @'
void main()
{
    float alpha = diffuseLookup(vary_texcoord0.xy).a;

    if (alpha < minimum_alpha)
    {
        discard;
    }

#if !defined(IS_FULLBRIGHT)
    alpha *= vertex_color.a;
#endif

    if (sl_alpha_capture_output == 0)
    {
        if (alpha < 0.05) // original shadow path
        {
            discard;
        }

        if (alpha < 0.88) // original semi-transparent shadow dither
        {
            if (fract(0.5*floor(target_pos_x / post_pos.w )) < 0.25)
            {
                discard;
            }
        }

        frag_color = vec4(1,1,1,1);
        return;
    }

    // Capture-only path: no shadow dither. PASS_ALPHA uses a low caller
    // cutoff and can preserve authored alpha; cutout callers request 1.
    if (alpha < 0.004)
    {
        discard;
    }

    float signal =
        sl_alpha_capture_output == 2 ? clamp(alpha, 0.0, 1.0) : 1.0;
    frag_color = vec4(signal, signal, signal, 1.0);
}
'@

$pbrAlphaMain = @'
void main()
{
    float alpha = texture(diffuseMap,vary_texcoord0.xy).a * vertex_color.a;

    if (alpha < minimum_alpha)
    {
        discard;
    }

    float signal =
        sl_alpha_capture_output == 2 ? clamp(alpha, 0.0, 1.0) : 1.0;
    frag_color = vec4(signal, signal, signal, 1.0);
}
'@

$treeShadowMain = @'
void main()
{
    float alpha = texture(diffuseMap, vary_texcoord0.xy).a;

    if (alpha < minimum_alpha)
    {
        discard;
    }

    float signal =
        sl_alpha_capture_output == 2 ? clamp(alpha, 0.0, 1.0) : 1.0;
    frag_color = vec4(signal, signal, signal, 1.0);
}
'@

$sa2 = Patch-ShaderMain $sa "shadowAlphaMaskF.glsl" $shadowAlphaMain
$pa2 = Patch-ShaderMain $pa "pbrShadowAlphaMaskF.glsl" $pbrAlphaMain
$ts2 = Patch-ShaderMain $ts "treeShadowF.glsl" $treeShadowMain

# ---------------------------------------------------------------------------
# Final structural validation BEFORE writing any file.
# ---------------------------------------------------------------------------

foreach ($check in @(
    @{ Text = $ht2; Needle = "ssrAlphaMaterial"; Label = "pipeline.h alpha target" },
    @{ Text = $ht2; Needle = "getAlphaCoverageTexture"; Label = "pipeline.h alpha getters" },
    @{ Text = $ct2; Needle = "SL_NATIVE_ALPHA_CAPTURE_V01"; Label = "capture marker" },
    @{ Text = $ct2; Needle = "SL_GetAlphaMaterialInfo"; Label = "material export" },
    @{ Text = $ct2; Needle = "SL_GetAlphaDepthInfo"; Label = "depth export" },
    @{ Text = $ct2; Needle = "SL_GetAlphaCoverageInfo"; Label = "coverage export" },
    @{ Text = $ct2; Needle = "renderAlphaObjects(bool rigged, F32 minimum_alpha, S32 alpha_capture_output)"; Label = "renderAlphaObjects signature" },
    @{ Text = $sa2; Needle = "sl_alpha_capture_output"; Label = "legacy shadow alpha capture uniform" },
    @{ Text = $pa2; Needle = "sl_alpha_capture_output"; Label = "PBR shadow alpha capture uniform" },
    @{ Text = $ts2; Needle = "sl_alpha_capture_output"; Label = "tree shadow capture uniform" }
)) {
    if (-not $check.Text.Contains($check.Needle)) {
        throw "Internal validation failed: missing $($check.Label). Nothing written."
    }
}

# ---------------------------------------------------------------------------
# Backups + writes.
# ---------------------------------------------------------------------------

$files = @(
    @{ Path = $pipelineCpp; Text = $ct2 },
    @{ Path = $pipelineH;   Text = $ht2 },
    @{ Path = $shadowAlpha; Text = $sa2 },
    @{ Path = $pbrAlpha;    Text = $pa2 },
    @{ Path = $treeShadow;  Text = $ts2 }
)

foreach ($f in $files) {
    $backup = "$($f.Path).sl-native-alpha-v0.1.bak"
    if (-not (Test-Path $backup)) {
        Copy-Item -LiteralPath $f.Path -Destination $backup
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($f in $files) {
    [System.IO.File]::WriteAllText($f.Path, $f.Text, $utf8NoBom)
}

Write-Host ""
Write-Host "Applied SL native alpha geometry v0.1."
Write-Host ""
Write-Host "Native exports:"
Write-Host "  SL_SetAlphaGeometryEnabled"
Write-Host "  SL_GetAlphaMaterialInfo  -> SL_ALPHA_MATERIAL"
Write-Host "  SL_GetAlphaDepthInfo     -> SL_DEPTH_ALPHA_NATIVE"
Write-Host "  SL_GetAlphaCoverageInfo  -> SL_ALPHA_COVERAGE"
Write-Host ""
Write-Host "Capture excludes:"
Write-Host "  SKY / WL_SKY / CLOUDS / PARTICLES / HUD / HUD_PARTICLES"
Write-Host ""
Write-Host "Next:"
Write-Host "  rebuild firestorm-bin, build SLNativeAlphaLink.addon, then run"
Write-Host "  NATIVE ALPHA - v0.1 Proof with GTAO disabled."
