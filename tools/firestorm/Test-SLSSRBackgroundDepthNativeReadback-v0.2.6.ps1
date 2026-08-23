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

if ($oldFn -match "SL SSR TEST A2 NATIVE READBACK") {
    throw "Test A2 native-readback patch already appears to be applied. Nothing changed."
}

$newFn = @'
void LLPipeline::renderSSRBackgroundDepth(LLCamera& camera)
{
    LL_PROFILE_ZONE_SCOPED_CATEGORY_DRAWPOOL;
    LL_PROFILE_GPU_ZONE("renderSSRBackgroundDepth");

    (void)camera;

    // SL SSR TEST A2 NATIVE READBACK
    //
    // Keep this pass clear-only, but instrument the native Firestorm side.
    // This distinguishes:
    //   A) pass never executes / returns early
    //   B) auxiliary FBO does not contain the clear value
    //   C) native FBO is correct but export/ReShade copy is wrong
    //
    // Search Firestorm.log for "SLSSR_BGDEPTH_A2".

    static bool logged_disabled = false;
    static bool logged_wrong_rt = false;
    static bool logged_cube = false;
    static bool logged_reflection = false;
    static bool logged_impostor = false;
    static bool logged_incomplete = false;
    static bool logged_success = false;

    if (!gSLSSRBackgroundDepthEnabled)
    {
        if (!logged_disabled)
        {
            LL_INFOS("SLSSR") << "SLSSR_BGDEPTH_A2 RETURN disabled" << LL_ENDL;
            logged_disabled = true;
        }
        return;
    }

    if (mRT != &mMainRT)
    {
        if (!logged_wrong_rt)
        {
            LL_INFOS("SLSSR") << "SLSSR_BGDEPTH_A2 RETURN wrong_render_target" << LL_ENDL;
            logged_wrong_rt = true;
        }
        return;
    }

    if (gCubeSnapshot)
    {
        if (!logged_cube)
        {
            LL_INFOS("SLSSR") << "SLSSR_BGDEPTH_A2 RETURN cube_snapshot" << LL_ENDL;
            logged_cube = true;
        }
        return;
    }

    if (sReflectionRender)
    {
        if (!logged_reflection)
        {
            LL_INFOS("SLSSR") << "SLSSR_BGDEPTH_A2 RETURN reflection_render" << LL_ENDL;
            logged_reflection = true;
        }
        return;
    }

    if (sImpostorRender)
    {
        if (!logged_impostor)
        {
            LL_INFOS("SLSSR") << "SLSSR_BGDEPTH_A2 RETURN impostor_render" << LL_ENDL;
            logged_impostor = true;
        }
        return;
    }

    LLRenderTarget& target = mMainRT.ssrBackgroundDepth;
    if (!target.isComplete())
    {
        if (!logged_incomplete)
        {
            LL_INFOS("SLSSR") << "SLSSR_BGDEPTH_A2 RETURN target_incomplete"
                              << " tex=" << target.getDepth()
                              << " size=" << target.getWidth() << "x" << target.getHeight()
                              << LL_ENDL;
            logged_incomplete = true;
        }
        return;
    }

    target.bindTarget();

    GLint bound_fbo = 0;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &bound_fbo);
    const GLenum fbo_status = glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER);

    float center_depth = -1.0f;
    float corner_depth = -1.0f;
    GLenum read_error = GL_NO_ERROR;

    {
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);

        GLdouble saved_depth_clear = 1.0;
        glGetDoublev(GL_DEPTH_CLEAR_VALUE, &saved_depth_clear);

        glClearDepth(1.0);
        target.clear(GL_DEPTH_BUFFER_BIT);
        glClearDepth(saved_depth_clear);

        // Force completion before native readback. Diagnostic only.
        glFinish();

        clear_glerror();

        const GLint cx = static_cast<GLint>(target.getWidth() / 2);
        const GLint cy = static_cast<GLint>(target.getHeight() / 2);

        glReadPixels(cx, cy, 1, 1, GL_DEPTH_COMPONENT, GL_FLOAT, &center_depth);
        glReadPixels(0, 0, 1, 1, GL_DEPTH_COMPONENT, GL_FLOAT, &corner_depth);

        read_error = glGetError();
    }

    if (!logged_success)
    {
        LL_INFOS("SLSSR")
            << "SLSSR_BGDEPTH_A2 EXECUTED"
            << " tex=" << target.getDepth()
            << " size=" << target.getWidth() << "x" << target.getHeight()
            << " fbo=" << bound_fbo
            << " fbo_status=" << static_cast<U32>(fbo_status)
            << " center=" << center_depth
            << " corner=" << corner_depth
            << " gl_error=" << static_cast<U32>(read_error)
            << LL_ENDL;

        logged_success = true;
    }

    target.flush();
}

'@

$bak = "$p.slssr-bgdepth-testA2-native-readback.bak"
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
Write-Host "Applied SL SSR TEST A2: native background-depth readback."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "This remains a clear-only pass."
Write-Host "After rebuild/run, search Firestorm.log for:"
Write-Host "  SLSSR_BGDEPTH_A2"
