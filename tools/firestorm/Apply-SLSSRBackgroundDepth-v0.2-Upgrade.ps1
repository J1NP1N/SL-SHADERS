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
        throw "${Label}: expected exactly one anchor in $Path, found $count. No file was modified by this replacement."
    }

    $text = $text.Replace($Old, $New)
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "patched: $Label"
}

$root = (Resolve-Path $FirestormRoot).Path
$pipelineH = Join-Path $root "indra\newview\pipeline.h"
$pipelineCpp = Join-Path $root "indra\newview\pipeline.cpp"

foreach ($p in @($pipelineH, $pipelineCpp)) {
    if (-not (Test-Path $p)) { throw "Missing expected Firestorm source file: $p" }
}

if (-not (Select-String -Path $pipelineCpp -Pattern "SL_GetSSRBackgroundDepthInfo" -Quiet)) {
    throw "v0.1 background-depth patch is not present. Apply v0.1 first; nothing changed."
}

if (Select-String -Path $pipelineCpp -Pattern "SL_GetSSRPrimaryDepthInfo" -Quiet) {
    throw "v0.2 native-primary upgrade already appears to be present. Nothing changed."
}

foreach ($p in @($pipelineH, $pipelineCpp)) {
    $bak = "$p.slssr-bgdepth-v0.2.bak"
    if (-not (Test-Path $bak)) {
        Copy-Item -LiteralPath $p -Destination $bak
    }
}

Replace-Exact -Path $pipelineH -Label "native primary depth public API" -Old @'
    U32 getSSRBackgroundDepthTexture() const;
    U32 getSSRBackgroundDepthWidth() const;
    U32 getSSRBackgroundDepthHeight() const;

    void renderGeomPostDeferred(LLCamera& camera);
'@ -New @'
    U32 getSSRBackgroundDepthTexture() const;
    U32 getSSRBackgroundDepthWidth() const;
    U32 getSSRBackgroundDepthHeight() const;

    // SL SSR v0.2: publish Firestorm's own main deferred depth too, so the
    // diagnostic compares two native Firestorm depth textures instead of
    // mixing native background depth with ReShade's generic SL_DEPTH choice.
    U32 getSSRPrimaryDepthTexture() const;
    U32 getSSRPrimaryDepthWidth() const;
    U32 getSSRPrimaryDepthHeight() const;

    void renderGeomPostDeferred(LLCamera& camera);
'@

Replace-Exact -Path $pipelineCpp -Label "native primary depth getters" -Old @'
U32 LLPipeline::getSSRBackgroundDepthHeight() const
{
    return mMainRT.ssrBackgroundDepth.getHeight();
}

#if LL_WINDOWS
'@ -New @'
U32 LLPipeline::getSSRBackgroundDepthHeight() const
{
    return mMainRT.ssrBackgroundDepth.getHeight();
}

U32 LLPipeline::getSSRPrimaryDepthTexture() const
{
    return mMainRT.deferredScreen.getDepth();
}

U32 LLPipeline::getSSRPrimaryDepthWidth() const
{
    return mMainRT.deferredScreen.getWidth();
}

U32 LLPipeline::getSSRPrimaryDepthHeight() const
{
    return mMainRT.deferredScreen.getHeight();
}

#if LL_WINDOWS
'@

Replace-Exact -Path $pipelineCpp -Label "native primary depth export" -Old @'
extern "C" SLSSR_NATIVE_EXPORT int SL_GetSSRBackgroundDepthInfo(
    unsigned int* texture,
    unsigned int* width,
    unsigned int* height)
{
'@ -New @'
extern "C" SLSSR_NATIVE_EXPORT int SL_GetSSRPrimaryDepthInfo(
    unsigned int* texture,
    unsigned int* width,
    unsigned int* height)
{
    if (!texture || !width || !height)
    {
        return 0;
    }

    *texture = gPipeline.getSSRPrimaryDepthTexture();
    *width = gPipeline.getSSRPrimaryDepthWidth();
    *height = gPipeline.getSSRPrimaryDepthHeight();

    return (*texture != 0 && *width != 0 && *height != 0) ? 1 : 0;
}

extern "C" SLSSR_NATIVE_EXPORT int SL_GetSSRBackgroundDepthInfo(
    unsigned int* texture,
    unsigned int* width,
    unsigned int* height)
{
'@

Write-Host ""
Write-Host "SL SSR background-depth v0.2 native-primary upgrade applied."
Write-Host "Modified:"
Write-Host "  indra/newview/pipeline.h"
Write-Host "  indra/newview/pipeline.cpp"
Write-Host ""
Write-Host "New export: SL_GetSSRPrimaryDepthInfo"
Write-Host "Rebuild Firestorm before installing the v0.2 ReShade bridge."
