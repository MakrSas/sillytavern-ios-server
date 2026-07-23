$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    'SillyTavernServer.xcodeproj/project.pbxproj',
    'SillyTavernServer.xcodeproj/xcshareddata/xcschemes/SillyTavernServer.xcscheme',
    'SillyTavernServer/Info.plist',
    'SillyTavernServer/Runtime/NodeRuntimeBridge.mm',
    'SillyTavernServer/Runtime/ServerController.swift',
    'SillyTavernServer/Resources/nodejs-project/main.js',
    'tests/smoke-runtime.mjs',
    '.github/workflows/build-prototype-ipa.yml',
    '.github/workflows/build-node22-and-ipa.yml'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $relativePath"
    }
}

[xml](Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'SillyTavernServer/Info.plist')) | Out-Null
[xml](Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'SillyTavernServer.xcodeproj/xcshareddata/xcschemes/SillyTavernServer.xcscheme')) | Out-Null
Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'SillyTavernServer/Resources/nodejs-project/package.json') |
    ConvertFrom-Json | Out-Null

$project = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'SillyTavernServer.xcodeproj/project.pbxproj')
foreach ($source in Get-ChildItem -Recurse -File -LiteralPath (Join-Path $repoRoot 'SillyTavernServer') |
    Where-Object { $_.Extension -in '.swift', '.mm' }) {
    if (-not $project.Contains($source.Name)) {
        throw "Source is absent from Xcode project: $($source.Name)"
    }
}

Write-Output 'Static source verification passed.'
