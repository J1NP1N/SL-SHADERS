param(
    [Parameter(Mandatory=$true)]
    [string]$FirestormRoot
)

$ErrorActionPreference = "Stop"

$pipelineCpp = Join-Path $FirestormRoot "indra\newview\pipeline.cpp"
if (-not (Test-Path $pipelineCpp)) {
    throw "Missing expected Firestorm source file: $pipelineCpp"
}

$text = [System.IO.File]::ReadAllText($pipelineCpp)

function Get-FunctionSpan([string]$source, [int]$signatureStart) {
    $brace = $source.IndexOf("{", $signatureStart)
    if ($brace -lt 0) {
        throw "Could not find function opening brace."
    }

    $depth = 0
    for ($i = $brace; $i -lt $source.Length; $i++) {
        $ch = $source[$i]
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

# This patch is intentionally scoped to the validated native avatar-backdepth pass.
# It must not touch the ReShade receiver or the Dstatic/Cstatic architecture.
if ($text -notmatch "SL_GetSSRAvatarBackDepthInfo") {
    throw "Expected validated native DavatarBack export SL_GetSSRAvatarBackDepthInfo. Nothing changed."
}
if ($text -notmatch "ssrAvatarBackDepth") {
    throw "Expected validated ssrAvatarBackDepth render target. Nothing changed."
}

$renderSig = "void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)"
$renderPos = $text.IndexOf($renderSig)
if ($renderPos -lt 0) {
    throw "Could not find renderSSRBackgroundDepth(). Nothing changed."
}

$renderSpan = Get-FunctionSpan $text $renderPos
$renderBlock = $text.Substring($renderSpan.Start, $renderSpan.End - $renderSpan.Start)

if ($renderBlock -match "SLSSR_AVBACK_COVERAGE_V0491") {
    throw "Native avatar-backdepth coverage fix v0.49.1 already appears to be applied. Nothing changed."
}
if ($renderBlock -notmatch "glCullFace\(GL_FRONT\)") {
    throw "Expected validated GL_FRONT avatar-backdepth culling. Nothing changed."
}
if ($renderBlock -notmatch "renderGLTFObjects\(LLRenderPass::PASS_GLTF_PBR,\s*false,\s*true\)") {
    throw "Expected validated opaque rigged GLTF draw in avatar-backdepth pass. Nothing changed."
}
if ($renderBlock -notmatch "for \(U32 type : color_types\)") {
    throw "Expected validated color_types rigged draw loop in avatar-backdepth pass. Nothing changed."
}

$oldPattern = '(?s)' +
    '(?<indent>[ \t]*)LLVertexBuffer::unbind\(\);\s*' +
    'gDeferredShadowProgram\.bind\(true\);\s*' +
    'gGL\.diffuseColor4f\(1\.f,\s*1\.f,\s*1\.f,\s*1\.f\);\s*' +
    'gGL\.getTexUnit\(0\)->unbind\(LLTexUnit::TT_TEXTURE\);\s*' +
    'for \(U32 type : color_types\)\s*\{\s*' +
    'renderObjects\(type,\s*false,\s*false,\s*true\);\s*' +
    '\}\s*' +
    'renderGLTFObjects\(LLRenderPass::PASS_GLTF_PBR,\s*false,\s*true\);\s*' +
    'gDeferredShadowProgram\.unbind\(\);'

$matches = [regex]::Matches($renderBlock, $oldPattern)
if ($matches.Count -ne 1) {
    throw "Expected exactly one validated opaque-only DavatarBack draw block; found $($matches.Count). Nothing changed."
}

$indent = $matches[0].Groups["indent"].Value

$newDrawBlock = @'
__INDENT__// SLSSR_AVBACK_COVERAGE_V0491
__INDENT__//
__INDENT__// Preserve the validated [D0, DavatarBack] contract and the existing
__INDENT__// GL_FRONT-cull/GL_LESS exit-depth target. The old pass only replayed
__INDENT__// opaque rigged render maps. Firestorm routes visible avatar content
__INDENT__// through additional shadow-capable classes (system avatar skin,
__INDENT__// alpha mask, material masks, alpha blend, and GLTF alpha mask), so
__INDENT__// those classes must participate in the same native exit-depth pass.
__INDENT__//
__INDENT__// Diagnostics report which formerly omitted rigged classes are present.
__INDENT__// Search Firestorm.log for "SLSSR_AVBACK_COVERAGE".
__INDENT__U32 slssr_avback_classes = 0;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_ALPHA_RIGGED) ? (1u << 0) : 0u;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_ALPHA_MASK_RIGGED) ? (1u << 1) : 0u;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_FULLBRIGHT_ALPHA_MASK_RIGGED) ? (1u << 2) : 0u;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_MATERIAL_ALPHA_MASK_RIGGED) ? (1u << 3) : 0u;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_SPECMAP_MASK_RIGGED) ? (1u << 4) : 0u;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_NORMMAP_MASK_RIGGED) ? (1u << 5) : 0u;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_NORMSPEC_MASK_RIGGED) ? (1u << 6) : 0u;
__INDENT__slssr_avback_classes |= hasRenderBatches(LLRenderPass::PASS_GLTF_PBR_ALPHA_MASK_RIGGED) ? (1u << 7) : 0u;
__INDENT__
__INDENT__static U32 slssr_avback_last_classes = 0xffffffffu;
__INDENT__if (slssr_avback_classes != slssr_avback_last_classes)
__INDENT__{
__INDENT__    LL_INFOS("SLSSR")
__INDENT__        << "SLSSR_AVBACK_COVERAGE"
__INDENT__        << " class_mask=" << slssr_avback_classes
__INDENT__        << " alpha=" << ((slssr_avback_classes >> 0) & 1u)
__INDENT__        << " alpha_mask=" << ((slssr_avback_classes >> 1) & 1u)
__INDENT__        << " fullbright_alpha_mask=" << ((slssr_avback_classes >> 2) & 1u)
__INDENT__        << " material_alpha_mask=" << ((slssr_avback_classes >> 3) & 1u)
__INDENT__        << " specmap_mask=" << ((slssr_avback_classes >> 4) & 1u)
__INDENT__        << " normmap_mask=" << ((slssr_avback_classes >> 5) & 1u)
__INDENT__        << " normspec_mask=" << ((slssr_avback_classes >> 6) & 1u)
__INDENT__        << " gltf_alpha_mask=" << ((slssr_avback_classes >> 7) & 1u)
__INDENT__        << LL_ENDL;
__INDENT__    slssr_avback_last_classes = slssr_avback_classes;
__INDENT__}
__INDENT__
__INDENT__// System avatar body/skin is owned by LLDrawPoolAvatar, not the
__INDENT__// rigged volume draw maps below. Reuse its native shadow passes while
__INDENT__// retaining the outer GL_FRONT cull so only exit-facing fragments win.
__INDENT__pushRenderTypeMask();
__INDENT__andRenderTypeMask(
__INDENT__    LLPipeline::RENDER_TYPE_AVATAR,
__INDENT__    LLPipeline::RENDER_TYPE_CONTROL_AV,
__INDENT__    END_RENDER_TYPES);
__INDENT__renderGeomShadow(camera);
__INDENT__popRenderTypeMask();
__INDENT__
__INDENT__// Opaque rigged attachments: preserve the validated v0.49 behavior.
__INDENT__LLVertexBuffer::unbind();
__INDENT__gDeferredShadowProgram.bind(true);
__INDENT__gGL.diffuseColor4f(1.f, 1.f, 1.f, 1.f);
__INDENT__gGL.getTexUnit(0)->unbind(LLTexUnit::TT_TEXTURE);
__INDENT__
__INDENT__for (U32 type : color_types)
__INDENT__{
__INDENT__    renderObjects(type, false, false, true);
__INDENT__}
__INDENT__
__INDENT__renderGLTFObjects(LLRenderPass::PASS_GLTF_PBR, false, true);
__INDENT__
__INDENT__// Match Firestorm's native shadow coverage for the remaining rigged
__INDENT__// material classes. This is geometry coverage, not an SSR heuristic.
__INDENT__const S32 slssr_sun_up = LLEnvironment::instance().getIsSunUp() ? 1 : 0;
__INDENT__const U32 slssr_target_width = LLRenderTarget::sCurResX;
__INDENT__
__INDENT__gDeferredShadowAlphaMaskProgram.bind(true);
__INDENT__LLGLSLShader::sCurBoundShaderPtr->uniform1i(LLShaderMgr::SUN_UP_FACTOR, slssr_sun_up);
__INDENT__LLGLSLShader::sCurBoundShaderPtr->uniform1f(
__INDENT__    LLShaderMgr::DEFERRED_SHADOW_TARGET_WIDTH,
__INDENT__    static_cast<float>(slssr_target_width));
__INDENT__renderMaskedObjects(LLRenderPass::PASS_ALPHA_MASK, true, true, true);
__INDENT__
__INDENT__renderAlphaObjects(true);
__INDENT__
__INDENT__gDeferredShadowFullbrightAlphaMaskProgram.bind(true);
__INDENT__LLGLSLShader::sCurBoundShaderPtr->uniform1i(LLShaderMgr::SUN_UP_FACTOR, slssr_sun_up);
__INDENT__LLGLSLShader::sCurBoundShaderPtr->uniform1f(
__INDENT__    LLShaderMgr::DEFERRED_SHADOW_TARGET_WIDTH,
__INDENT__    static_cast<float>(slssr_target_width));
__INDENT__renderFullbrightMaskedObjects(
__INDENT__    LLRenderPass::PASS_FULLBRIGHT_ALPHA_MASK,
__INDENT__    true,
__INDENT__    true,
__INDENT__    true);
__INDENT__
__INDENT__gDeferredTreeShadowProgram.bind(true);
__INDENT__LLGLSLShader::sCurBoundShaderPtr->setMinimumAlpha(ALPHA_BLEND_CUTOFF);
__INDENT__renderMaskedObjects(LLRenderPass::PASS_NORMSPEC_MASK, true, false, true);
__INDENT__renderMaskedObjects(LLRenderPass::PASS_MATERIAL_ALPHA_MASK, true, false, true);
__INDENT__renderMaskedObjects(LLRenderPass::PASS_SPECMAP_MASK, true, false, true);
__INDENT__renderMaskedObjects(LLRenderPass::PASS_NORMMAP_MASK, true, false, true);
__INDENT__
__INDENT__gDeferredShadowGLTFAlphaMaskProgram.bind(true);
__INDENT__LLGLSLShader::sCurBoundShaderPtr->uniform1i(LLShaderMgr::SUN_UP_FACTOR, slssr_sun_up);
__INDENT__LLGLSLShader::sCurBoundShaderPtr->uniform1f(
__INDENT__    LLShaderMgr::DEFERRED_SHADOW_TARGET_WIDTH,
__INDENT__    static_cast<float>(slssr_target_width));
__INDENT__
__INDENT__gGL.loadMatrix(gGLModelView);
__INDENT__gGLLastMatrix = NULL;
__INDENT__mAlphaMaskPool->pushRiggedGLTFBatches(LLRenderPass::PASS_GLTF_PBR_ALPHA_MASK_RIGGED);
__INDENT__gGL.loadMatrix(gGLModelView);
__INDENT__gGLLastMatrix = NULL;
__INDENT__
__INDENT__gDeferredShadowGLTFAlphaMaskProgram.unbind();
'@

$newDrawBlock = $newDrawBlock.Replace("__INDENT__", $indent).TrimEnd("`r", "`n")

$drawMatch = $matches[0]
$renderBlock2 =
    $renderBlock.Substring(0, $drawMatch.Index) +
    $newDrawBlock +
    $renderBlock.Substring($drawMatch.Index + $drawMatch.Length)

if ($renderBlock2 -eq $renderBlock) {
    throw "Internal error: DavatarBack draw block replacement produced no change."
}

$text2 = $text.Substring(0, $renderSpan.Start) + $renderBlock2 + $text.Substring($renderSpan.End)

$backup = "$pipelineCpp.slssr-avback-coverage-v0.49.1.bak"
if (-not (Test-Path $backup)) {
    Copy-Item -LiteralPath $pipelineCpp -Destination $backup
}

[System.IO.File]::WriteAllText(
    $pipelineCpp,
    $text2,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Applied SL SSR native avatar-backdepth coverage fix v0.49.1."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "Preserved:"
Write-Host "  D0 / SL_DEPTH_PRIMARY_NATIVE"
Write-Host "  Dstatic / SL_DEPTH_BACKGROUND"
Write-Host "  Cstatic / SL_COLOR_BACKGROUND"
Write-Host "  [D0, DavatarBack] receiver contract"
Write-Host ""
Write-Host "Added native DavatarBack coverage:"
Write-Host "  system avatar shadow pool"
Write-Host "  rigged alpha blend"
Write-Host "  rigged alpha mask + fullbright alpha mask"
Write-Host "  rigged legacy material/spec/normal/normspec masks"
Write-Host "  rigged GLTF/PBR alpha mask"
Write-Host ""
Write-Host "Runtime diagnostic:"
Write-Host '  Get-Content "$env:APPDATA\Firestorm_x64\logs\Firestorm.log" -Wait | Select-String "SLSSR_AVBACK_COVERAGE"'
Write-Host ""
Write-Host "Build:"
Write-Host '  cmake --build "C:\firestorm-slssr\phoenix-firestorm\build-vc170-64" --config Release --target firestorm-bin'
