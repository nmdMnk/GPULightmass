param(
    [switch]$ForceDownload,
    [switch]$ForceBuild
)

$ErrorActionPreference = 'Stop'

$TbbVersion = '2023.0.0'
$EmbreeVersion = '4.4.1'
$TbbSha256 = 'ddb0d40fb263b490c4d22423193fc1832ee3aee8ab61f6ef3757b6fa4104276c'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$ExternalDir = Join-Path $RepoRoot 'External'
$DownloadDir = Join-Path $ExternalDir '_downloads'

$TbbDir = Join-Path $ExternalDir "oneapi-tbb-$TbbVersion"
$EmbreeSourceDir = Join-Path $ExternalDir "embree-$EmbreeVersion"
$EmbreeBuildDir = Join-Path $ExternalDir 'embree-build-mt-static'
$EmbreeInstallDir = Join-Path $ExternalDir 'embree'

$TbbArchive = Join-Path $DownloadDir "oneapi-tbb-$TbbVersion-win.zip"
$EmbreeArchive = Join-Path $DownloadDir "embree-$EmbreeVersion-source.zip"
$TbbUrl = "https://github.com/uxlfoundation/oneTBB/releases/download/v$TbbVersion/oneapi-tbb-$TbbVersion-win.zip"
$EmbreeUrl = "https://github.com/RenderKit/embree/archive/refs/tags/v$EmbreeVersion.zip"

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )

    if ((Test-Path -LiteralPath $OutputPath) -and -not $ForceDownload) {
        Write-Step "Using cached $(Split-Path -Leaf $OutputPath)"
        return
    }

    Write-Step "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutputPath
}

function Assert-Sha256 {
    param(
        [string]$Path,
        [string]$ExpectedHash
    )

    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actualHash -ne $ExpectedHash.ToLowerInvariant()) {
        throw "SHA256 mismatch for $Path. Expected $ExpectedHash, got $actualHash."
    }
}

function Expand-ZipIfNeeded {
    param(
        [string]$ArchivePath,
        [string]$ExpectedDir
    )

    if ((Test-Path -LiteralPath $ExpectedDir) -and -not $ForceDownload) {
        Write-Step "Using existing $(Split-Path -Leaf $ExpectedDir)"
        return
    }

    Write-Step "Extracting $(Split-Path -Leaf $ArchivePath)"
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExternalDir -Force
}

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    Write-Step "$FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Assert-Path {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required path is missing: $Path"
    }
}

function Test-EmbreeInstalled {
    return ((Test-Path -LiteralPath (Join-Path $EmbreeInstallDir 'include')) -and
            (Test-Path -LiteralPath (Join-Path $EmbreeInstallDir 'lib')))
}

Ensure-Directory $ExternalDir
Ensure-Directory $DownloadDir

if ((Test-Path -LiteralPath $TbbDir) -and -not $ForceDownload) {
    Write-Step "Using existing $(Split-Path -Leaf $TbbDir)"
} else {
    Download-File -Url $TbbUrl -OutputPath $TbbArchive
    Assert-Sha256 -Path $TbbArchive -ExpectedHash $TbbSha256
    Expand-ZipIfNeeded -ArchivePath $TbbArchive -ExpectedDir $TbbDir
}

if ((Test-Path -LiteralPath $EmbreeSourceDir) -and -not $ForceDownload) {
    Write-Step "Using existing $(Split-Path -Leaf $EmbreeSourceDir)"
} else {
    Download-File -Url $EmbreeUrl -OutputPath $EmbreeArchive
    Expand-ZipIfNeeded -ArchivePath $EmbreeArchive -ExpectedDir $EmbreeSourceDir
}

if (-not (Test-Path -LiteralPath $EmbreeSourceDir)) {
    $sourceRoot = Get-ChildItem -LiteralPath $ExternalDir -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'CMakeLists.txt') } |
        Where-Object { $_.Name -like 'embree-*' } |
        Select-Object -First 1

    if (-not $sourceRoot) {
        throw "Could not find extracted Embree source directory."
    }

    Rename-Item -LiteralPath $sourceRoot.FullName -NewName "embree-$EmbreeVersion"
}

if ((Test-EmbreeInstalled) -and -not $ForceBuild) {
    Write-Step "Using existing Embree install"
} else {
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        throw "CMake was not found in PATH. Install CMake before running this script."
    }

    Ensure-Directory $EmbreeBuildDir

    $configureArgs = @(
        '-S', $EmbreeSourceDir,
        '-B', $EmbreeBuildDir,
        '-G', 'Visual Studio 17 2022',
        '-A', 'x64',
        "-DCMAKE_INSTALL_PREFIX=$EmbreeInstallDir",
        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>',
        '-DEMBREE_STATIC_LIB=ON',
        '-DEMBREE_MAX_ISA=AVX2',
        '-DEMBREE_ISPC_SUPPORT=OFF',
        '-DEMBREE_TASKING_SYSTEM=TBB',
        '-DEMBREE_TBB_COMPONENT=tbb',
        "-DEMBREE_TBB_ROOT=$TbbDir",
        "-DTBB_ROOT=$TbbDir",
        '-DEMBREE_TUTORIALS=OFF'
    )

    Invoke-Checked -FilePath 'cmake' -Arguments $configureArgs
    Invoke-Checked -FilePath 'cmake' -Arguments @('--build', $EmbreeBuildDir, '--config', 'Release', '--target', 'INSTALL', '--', '/m')
}

$requiredPaths = @(
    (Join-Path $TbbDir 'include'),
    (Join-Path $TbbDir 'lib\intel64\vc14'),
    (Join-Path $TbbDir 'redist\intel64\vc14\tbb12.dll'),
    (Join-Path $EmbreeInstallDir 'include'),
    (Join-Path $EmbreeInstallDir 'lib')
)

foreach ($path in $requiredPaths) {
    Assert-Path $path
}

Write-Step 'External dependencies are ready.'
Write-Host "TBB:    $TbbDir"
Write-Host "Embree: $EmbreeInstallDir"
