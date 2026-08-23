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

$old = @'
    target.bindTarget();
    target.clear(GL_DEPTH_BUFFER_BIT);

    {
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);
        LLGLEnable cull(GL_CULL_FACE);
'@

$new = @'
    target.bindTarget();

    {
        // SL SSR v0.2.3: glClear(GL_DEPTH_BUFFER_BIT) obeys the depth write mask.
        // renderGeomDeferred may leave depth writes disabled, so establish the
        // writable GL_LESS state before clearing this auxiliary depth target.
        LLGLDepthTest depth(GL_TRUE, GL_TRUE, GL_LESS);

        GLdouble saved_depth_clear = 1.0;
        glGetDoublev(GL_DEPTH_CLEAR_VALUE, &saved_depth_clear);
        glClearDepth(1.0);
        target.clear(GL_DEPTH_BUFFER_BIT);
        glClearDepth(saved_depth_clear);

        LLGLEnable cull(GL_CULL_FACE);
'@

$count = ([regex]::Matches($text, [regex]::Escape($old))).Count
if ($count -ne 1) {
    throw "Expected exactly one v0.1 background-depth clear block, found $count. Nothing changed."
}

$bak = "$p.slssr-bgdepth-v0.2.3.bak"
if (-not (Test-Path $bak)) {
    Copy-Item -LiteralPath $p -Destination $bak
}

$text = $text.Replace($old, $new)
[System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Applied SL SSR background-depth v0.2.3 clear-state fix."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "Next: rebuild Firestorm and copy the rebuilt EXE over the installed custom viewer."
