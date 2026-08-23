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

if ($oldFn -notmatch "SL SSR TEST C2 DRAW INSTRUMENTATION") {
    throw "Expected TEST C2 draw instrumentation is not active. Nothing changed."
}
if ($oldFn -match "SL SSR TEST C3 RENDER MAP COUNTS") {
    throw "TEST C3 render-map instrumentation already appears to be applied. Nothing changed."
}

$newFn = @'
void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)
{
    LL_PROFILE_ZONE_SCOPED_CATEGORY_DRAWPOOL;
    LL_PROFILE_GPU_ZONE("renderSSRBackgroundDepth");

    (void)camera;

    // SL SSR TEST C3 RENDER MAP COUNTS
    //
    // One-frame diagnostic:
    //   * prove whether sCull render maps still contain DrawInfos here
    //   * report total index counts / null VBs / avatar-tagged entries
    //   * report rasterizer state
    //   * issue the actual static draws and read native depth afterward
    //
    // Search Firestorm.log for "SLSSR_BGDEPTH_C3".

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

    static bool instrumented = false;
    const bool instrument_this_frame = !instrumented;

    const bool saved_shadow_render = sShadowRender;
    const U32 saved_occlusion = sUseOcclusion;

    sShadowRender = true;
    sUseOcclusion = 0;

    target.bindTarget();

    {
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);

        GLdouble saved_depth_clear = 1.0;
        glGetDoublev(GL_DEPTH_CLEAR_VALUE, &saved_depth_clear);
        glClearDepth(1.0);
        target.clear(GL_DEPTH_BUFFER_BIT);
        glClearDepth(saved_depth_clear);

        LLGLEnable cull(GL_CULL_FACE);

        LLVertexBuffer::unbind();
        gDeferredShadowProgram.bind(false);
        gGL.diffuseColor4f(1.f, 1.f, 1.f, 1.f);
        gGL.getTexUnit(0)->unbind(LLTexUnit::TT_TEXTURE);

        if (instrument_this_frame)
        {
            GLint viewport[4] = { 0, 0, 0, 0 };
            GLint scissor_box[4] = { 0, 0, 0, 0 };
            GLint current_program = 0;
            GLint depth_func = 0;
            GLint front_face = 0;
            GLint cull_face_mode = 0;
            GLboolean depth_write = GL_FALSE;

            glGetIntegerv(GL_VIEWPORT, viewport);
            glGetIntegerv(GL_SCISSOR_BOX, scissor_box);
            glGetIntegerv(GL_CURRENT_PROGRAM, &current_program);
            glGetIntegerv(GL_DEPTH_FUNC, &depth_func);
            glGetIntegerv(GL_FRONT_FACE, &front_face);
            glGetIntegerv(GL_CULL_FACE_MODE, &cull_face_mode);
            glGetBooleanv(GL_DEPTH_WRITEMASK, &depth_write);

            LL_INFOS("SLSSR")
                << "SLSSR_BGDEPTH_C3 STATE"
                << " sCull=" << (sCull ? 1 : 0)
                << " program=" << current_program
                << " viewport=" << viewport[0] << "," << viewport[1] << ","
                << viewport[2] << "," << viewport[3]
                << " scissor_enabled=" << (glIsEnabled(GL_SCISSOR_TEST) ? 1 : 0)
                << " scissor=" << scissor_box[0] << "," << scissor_box[1] << ","
                << scissor_box[2] << "," << scissor_box[3]
                << " cull_enabled=" << (glIsEnabled(GL_CULL_FACE) ? 1 : 0)
                << " cull_mode=" << cull_face_mode
                << " front_face=" << front_face
                << " rasterizer_discard=" << (glIsEnabled(GL_RASTERIZER_DISCARD) ? 1 : 0)
                << " depth_func=" << depth_func
                << " depth_write=" << (depth_write ? 1 : 0)
                << LL_ENDL;

            for (U32 type : types)
            {
                U32 drawinfos = 0;
                U32 null_vbs = 0;
                U32 avatar_entries = 0;
                U64 indices = 0;

                auto* begin = beginRenderMap(type);
                auto* end = endRenderMap(type);

                for (LLCullResult::drawinfo_iterator i = begin; i != end; )
                {
                    LLDrawInfo* pparams = *i;
                    LLCullResult::increment_iterator(i, end);

                    ++drawinfos;

                    if (!pparams)
                    {
                        continue;
                    }

                    indices += pparams->mCount;

                    if (pparams->mVertexBuffer == nullptr)
                    {
                        ++null_vbs;
                    }

                    if (pparams->mAvatar != nullptr)
                    {
                        ++avatar_entries;
                    }
                }

                LL_INFOS("SLSSR")
                    << "SLSSR_BGDEPTH_C3 MAP"
                    << " type=" << type
                    << " has=" << (hasRenderBatches(type) ? 1 : 0)
                    << " drawinfos=" << drawinfos
                    << " indices=" << indices
                    << " null_vbs=" << null_vbs
                    << " avatar_entries=" << avatar_entries
                    << LL_ENDL;
            }
        }

        for (U32 type : types)
        {
            renderObjects(type, false, false, false);
        }

        renderGLTFObjects(LLRenderPass::PASS_GLTF_PBR, false, false);

        gDeferredShadowProgram.unbind();
    }

    if (instrument_this_frame)
    {
        glFinish();
        clear_glerror();

        const U32 width = target.getWidth();
        const U32 height = target.getHeight();
        std::vector<float> pixels;
        pixels.resize(static_cast<size_t>(width) * static_cast<size_t>(height), 1.0f);

        glReadPixels(
            0,
            0,
            static_cast<GLsizei>(width),
            static_cast<GLsizei>(height),
            GL_DEPTH_COMPONENT,
            GL_FLOAT,
            pixels.data());

        const GLenum read_error = glGetError();

        float min_depth = 1.0f;
        float max_depth = 0.0f;
        U64 changed_pixels = 0;

        for (float z : pixels)
        {
            min_depth = llmin(min_depth, z);
            max_depth = llmax(max_depth, z);

            if (z < 0.999999f)
            {
                ++changed_pixels;
            }
        }

        LL_INFOS("SLSSR")
            << "SLSSR_BGDEPTH_C3 RESULT"
            << " min=" << min_depth
            << " max=" << max_depth
            << " changed_pixels=" << changed_pixels
            << " total_pixels=" << pixels.size()
            << " gl_error=" << static_cast<U32>(read_error)
            << LL_ENDL;

        instrumented = true;
    }

    target.flush();

    sUseOcclusion = saved_occlusion;
    sShadowRender = saved_shadow_render;
}

'@

$bak = "$p.slssr-bgdepth-testC3-render-map-counts.bak"
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
Write-Host "Applied SL SSR TEST C3: render-map counts and rasterizer state."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "After rebuild/run, search Firestorm.log for:"
Write-Host "  SLSSR_BGDEPTH_C3"
