param(
    [Parameter(Mandatory=$true)]
    [string]$FirestormRoot
)

$ErrorActionPreference = "Stop"

$pipelineCpp = Join-Path $FirestormRoot "indra\newview\pipeline.cpp"
$basePatch = Join-Path $PSScriptRoot "Apply-SLNativeAlphaGeometry-v0.1.ps1"

if (-not (Test-Path $pipelineCpp)) {
    throw "Missing expected Firestorm source file: $pipelineCpp"
}

# v0.1.1 is the build entry point. If the base v0.1 classification patch has
# not been applied yet, apply it first.
$ct = [System.IO.File]::ReadAllText($pipelineCpp)
if ($ct -notmatch "SL_NATIVE_ALPHA_CAPTURE_V01") {
    if (-not (Test-Path $basePatch)) {
        throw "Base patch is not applied and sibling Apply-SLNativeAlphaGeometry-v0.1.ps1 is missing."
    }

    & $basePatch -FirestormRoot $FirestormRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Base native-alpha v0.1 patch failed."
    }

    $ct = [System.IO.File]::ReadAllText($pipelineCpp)
}

if ($ct -notmatch "SL_NATIVE_ALPHA_CAPTURE_V01") {
    throw "Base native-alpha v0.1 capture marker was not found after apply."
}

if ($ct -match "SL_NATIVE_ALPHA_CAPTURE_V011") {
    Write-Host "SL native alpha geometry v0.1.1 is already applied. Nothing changed."
    exit 0
}

# v0.1 correctly classifies by Firestorm render category, but its generated
# capture unbound gDeferredShadowAlphaMaskProgram before renderAlphaObjects().
# Firestorm's own shadow path intentionally keeps that shader bound across the
# alpha-mask and alpha-blend draws. renderAlphaObjects() uses the current bound
# shader for minimum_alpha/capture uniforms, so the v0.1 ordering is unsafe.
#
# v0.1 also leaves sl_alpha_capture_output non-zero on shared shadow programs.
# GLSL uniforms persist across binds, so normal Firestorm shadows could inherit
# capture mode later. v0.1.1 resets every shared program before unbinding it.

$oldAlpha = @'
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
'@

$newAlpha = @'
                    renderMaskedObjects(
                        LLRenderPass::PASS_ALPHA_MASK,
                        true,
                        true,
                        sl_rigged);

                    // True blended alpha. Firestorm's native shadow path keeps
                    // gDeferredShadowAlphaMaskProgram bound across the mask and
                    // alpha-group draws; renderAlphaObjects() relies on that
                    // current shader for minimum-alpha/capture uniforms.
                    renderAlphaObjects(
                        sl_rigged,
                        0.004f,
                        sl_blend_output);

                    // Capture state must never leak into ordinary Firestorm
                    // shadow rendering.
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, 0);
                    LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(
                        ALPHA_BLEND_CUTOFF);
                    gDeferredShadowAlphaMaskProgram.unbind();
'@

$oldFullbright = @'
                    renderFullbrightMaskedObjects(
                        LLRenderPass::PASS_FULLBRIGHT_ALPHA_MASK,
                        true,
                        true,
                        sl_rigged);
                    gDeferredShadowFullbrightAlphaMaskProgram.unbind();
'@

$newFullbright = @'
                    renderFullbrightMaskedObjects(
                        LLRenderPass::PASS_FULLBRIGHT_ALPHA_MASK,
                        true,
                        true,
                        sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, 0);
                    gDeferredShadowFullbrightAlphaMaskProgram.unbind();
'@

$oldTreeBegin = @'
                    // Legacy material alpha-mask variants.
                    gDeferredTreeShadowProgram.bind(sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, sl_mask_output);
'@

$newTreeBegin = @'
                    // Legacy material alpha-mask variants.
                    gDeferredTreeShadowProgram.bind(sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(
                        ALPHA_BLEND_CUTOFF);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, sl_mask_output);
'@

$oldTreeEnd = @'
                    renderMaskedObjects(
                        LLRenderPass::PASS_NORMMAP_MASK,
                        true, false, sl_rigged);
                    gDeferredTreeShadowProgram.unbind();
'@

$newTreeEnd = @'
                    renderMaskedObjects(
                        LLRenderPass::PASS_NORMMAP_MASK,
                        true, false, sl_rigged);
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, 0);
                    LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(
                        ALPHA_BLEND_CUTOFF);
                    gDeferredTreeShadowProgram.unbind();
'@

$oldGltfEnd = @'
                    gGL.loadMatrix(gGLModelView);
                    gGLLastMatrix = NULL;
                    gDeferredShadowGLTFAlphaMaskProgram.unbind();
'@

$newGltfEnd = @'
                    gGL.loadMatrix(gGLModelView);
                    gGLLastMatrix = NULL;
                    LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                        sSLAlphaCaptureOutput, 0);
                    gDeferredShadowGLTFAlphaMaskProgram.unbind();
'@

$oldGrass = @'
                renderObjects(LLRenderPass::PASS_GRASS, true);
                gDeferredTreeShadowProgram.unbind();
'@

$newGrass = @'
                renderObjects(LLRenderPass::PASS_GRASS, true);
                LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                    sSLAlphaCaptureOutput, 0);
                LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(
                    ALPHA_BLEND_CUTOFF);
                gDeferredTreeShadowProgram.unbind();
'@

$oldTreePoolEnd = @'
                    sl_tree_pool->renderShadow(0);
                    sl_tree_pool->endShadowPass(0);
                }
            }

            alpha_target.flush();
'@

$newTreePoolEnd = @'
                    sl_tree_pool->renderShadow(0);
                    sl_tree_pool->endShadowPass(0);
                }

                // A tree pool may have rebound the shared tree shadow program.
                // Force its capture uniform back to ordinary Firestorm mode.
                gDeferredTreeShadowProgram.bind(false);
                LLGLSLShader::sCurBoundShaderPtr->uniform1i(
                    sSLAlphaCaptureOutput, 0);
                LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(
                    ALPHA_BLEND_CUTOFF);
                gDeferredTreeShadowProgram.unbind();
            }

            alpha_target.flush();
'@

function Replace-ExactOnce(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label)
{
    $count = ([regex]::Matches(
        $Text,
        [regex]::Escape($Old))).Count

    if ($count -ne 1) {
        throw "Expected exactly one '$Label' block; found $count. Nothing written."
    }

    return $Text.Replace($Old, $New)
}

$ct2 = $ct
$ct2 = Replace-ExactOnce $ct2 $oldAlpha       $newAlpha       "alpha-mask / PASS_ALPHA ordering"
$ct2 = Replace-ExactOnce $ct2 $oldFullbright  $newFullbright  "fullbright alpha-mask reset"
$ct2 = Replace-ExactOnce $ct2 $oldTreeBegin   $newTreeBegin   "legacy mask setup"
$ct2 = Replace-ExactOnce $ct2 $oldTreeEnd     $newTreeEnd     "legacy mask reset"

# There is one GLTF capture block in the generated alpha-capture lambda.
# Scope the replacement to renderSSRBackgroundDepth() so existing DavatarBack
# GLTF code is not touched.
$renderSig = "void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)"
$renderStart = $ct2.IndexOf($renderSig)
if ($renderStart -lt 0) {
    throw "renderSSRBackgroundDepth() not found. Nothing written."
}

$nextMarker = $ct2.IndexOf(
    "// Render all of our geometry that's required after our deferred pass.",
    $renderStart)

if ($nextMarker -lt 0) {
    throw "Could not locate end of renderSSRBackgroundDepth() region. Nothing written."
}

$prefix = $ct2.Substring(0, $renderStart)
$renderRegion = $ct2.Substring($renderStart, $nextMarker - $renderStart)
$suffix = $ct2.Substring($nextMarker)

$renderRegion = Replace-ExactOnce $renderRegion $oldGltfEnd $newGltfEnd "alpha GLTF reset"
$renderRegion = Replace-ExactOnce $renderRegion $oldGrass $newGrass "grass reset"
$renderRegion = Replace-ExactOnce $renderRegion $oldTreePoolEnd $newTreePoolEnd "tree-pool reset"

$markerNeedle = "    // SL_NATIVE_ALPHA_CAPTURE_V01"
$markerCount = ([regex]::Matches(
    $renderRegion,
    [regex]::Escape($markerNeedle))).Count

if ($markerCount -ne 1) {
    throw "Expected exactly one base alpha-capture marker; found $markerCount."
}

$renderRegion = $renderRegion.Replace(
    $markerNeedle,
    "    // SL_NATIVE_ALPHA_CAPTURE_V011`r`n" +
    "    // v0.1.1: preserve native shader binding order and reset capture uniforms.`r`n" +
    $markerNeedle
)

$ct2 = $prefix + $renderRegion + $suffix

# Final fail-closed checks.
foreach ($needle in @(
    "SL_NATIVE_ALPHA_CAPTURE_V011",
    "renderAlphaObjects(",
    "sSLAlphaCaptureOutput, 0",
    "RENDER_TYPE_CLOUDS",
    "PASS_GLTF_PBR_ALPHA_MASK_RIGGED"
)) {
    if (-not $ct2.Contains($needle)) {
        throw "Internal validation failed: missing '$needle'. Nothing written."
    }
}

$backup = "$pipelineCpp.sl-native-alpha-v0.1.1.bak"
if (-not (Test-Path $backup)) {
    Copy-Item -LiteralPath $pipelineCpp -Destination $backup
}

[System.IO.File]::WriteAllText(
    $pipelineCpp,
    $ct2,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Applied SL native alpha geometry v0.1.1."
Write-Host ""
Write-Host "Correctness fixes over v0.1:"
Write-Host "  PASS_ALPHA runs while Firestorm's shadow-alpha shader is still bound"
Write-Host "  capture-only uniforms reset to 0 on every shared shadow program"
Write-Host "  legacy material-mask cutoff explicitly restored"
Write-Host ""
Write-Host "Classification remains renderer-native:"
Write-Host "  PASS_ALPHA / alpha groups"
Write-Host "  alpha-mask / fullbright-mask / legacy material masks"
Write-Host "  GLTF/PBR alpha mask, static + rigged"
Write-Host "  grass + system-tree cutouts"
Write-Host "  SKY / WL_SKY / CLOUDS / PARTICLES / HUD excluded"
Write-Host ""
Write-Host "Build:"
Write-Host '  cmake --build "C:\firestorm-slssr\phoenix-firestorm\build-vc170-64" --config Release --target firestorm-bin'
