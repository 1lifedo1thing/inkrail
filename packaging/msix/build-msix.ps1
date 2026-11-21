# Creates an unsigned x64 MSIX from the existing GitHub Release ZIP.
# Intended for submission in an MSIX/PWA Microsoft Store product.
# Run on a Windows GitHub Actions runner; no Windows build from source is attempted.

param(
    [string]$ReleaseTag = $env:SOURCE_TAG,
    [string]$Version = $env:PACKAGE_VERSION,
    [string]$IdentityName = $env:MSIX_IDENTITY_NAME,
    [string]$Publisher = $env:MSIX_PUBLISHER,
    [string]$PublisherDisplayName = $env:MSIX_PUBLISHER_DISPLAY_NAME
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($setting in @{
    ReleaseTag = $ReleaseTag
    Version = $Version
    IdentityName = $IdentityName
    Publisher = $Publisher
    PublisherDisplayName = $PublisherDisplayName
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace($setting.Value)) {
        throw "Missing $($setting.Key). Configure MSIX_* repository variables and workflow inputs."
    }
}

$numbers = $Version.Split('.')
if ($numbers.Count -ne 4 -or ($numbers | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0) {
    throw 'Package version must have four numeric parts, e.g. 1.0.0.0.'
}
$parts = @($numbers | ForEach-Object { [int]$_ })
if ($parts[0] -lt 1 -or $parts[3] -ne 0 -or (@($parts | Where-Object { $_ -gt 65535 })).Count -gt 0) {
    throw 'Microsoft Store MSIX versions need Major >= 1, each part <= 65535, and the fourth part = 0.'
}
if ($ReleaseTag -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') {
    throw 'The release tag contains unexpected characters.'
}

# GitHub Actions Windows runners have the Windows SDK and MakeAppx.exe.
$kitRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$makeAppx = Get-ChildItem -LiteralPath $kitRoot -Recurse -Filter MakeAppx.exe -File |
    Where-Object { $_.FullName -match '[\\/]x64[\\/]MakeAppx\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $makeAppx) {
    throw 'Windows SDK x64 MakeAppx.exe not found on runner.'
}

$work = Join-Path $env:RUNNER_TEMP 'inkrail-msix-work'
$extractDir = Join-Path $work 'extracted'
$staging = Join-Path $work 'package'
$outputDir = Join-Path (Get-Location) 'dist-msix'
New-Item -ItemType Directory -Force -Path $extractDir, $staging, $outputDir | Out-Null

$zipFile = Join-Path $work 'Inkrail-Windows-x64.zip'
$url = "https://github.com/Aaryanverma/inkrail/releases/download/$ReleaseTag/Inkrail-Windows-x64.zip"
Write-Host "Downloading Windows build from $url"
Invoke-WebRequest -Uri $url -OutFile $zipFile
Expand-Archive -LiteralPath $zipFile -DestinationPath $extractDir -Force

# Preserve the original executable's neighbouring DLLs, HTML/CSS, and assets.
# Support either a ZIP with a top-level folder or files directly at ZIP root.
$exe = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter 'Inkrail.exe' |
    Select-Object -First 1
if (-not $exe) {
    throw 'Inkrail.exe not found in release ZIP. Review the archive layout.'
}
Get-ChildItem -LiteralPath $exe.DirectoryName -Force |
    Copy-Item -Destination $staging -Recurse -Force
if (-not (Test-Path (Join-Path $staging 'Inkrail.exe'))) {
    throw 'Inkrail.exe was not copied to the package root.'
}

# Create real PNG assets from the existing Inkrail app icon in the repository.
$icon = Join-Path (Get-Location) 'Sources\Inkrail\Resources\AppIcon.png'
if (-not (Test-Path $icon)) {
    throw "Icon missing: $icon. Update the script to use the correct app icon path."
}
$assets = Join-Path $staging 'MSIXAssets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile($icon)
try {
    foreach ($spec in @(
        @{ Name = 'StoreLogo.png'; Size = 50 },
        @{ Name = 'Square44x44Logo.png'; Size = 44 },
        @{ Name = 'Square150x150Logo.png'; Size = 150 }
    )) {
        $size = [int]$spec.Size
        $bmp = [System.Drawing.Bitmap]::new($size, $size)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.DrawImage($src, 0, 0, $size, $size)
            }
            finally { $graphics.Dispose() }
            $bmp.Save((Join-Path $assets $spec.Name), [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $bmp.Dispose() }
    }
}
finally { $src.Dispose() }

# XML-escape identity values; these MUST match Partner Center exactly.
$identityXml = [System.Security.SecurityElement]::Escape($IdentityName)
$publisherXml = [System.Security.SecurityElement]::Escape($Publisher)
$displayXml = [System.Security.SecurityElement]::Escape($PublisherDisplayName)

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap uap10 rescap">
  <Identity Name="$identityXml" Publisher="$publisherXml" Version="$Version" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Inkrail</DisplayName>
    <PublisherDisplayName>$displayXml</PublisherDisplayName>
    <Logo>MSIXAssets\StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="App" Executable="Inkrail.exe"
      uap10:RuntimeBehavior="packagedClassicApp" uap10:TrustLevel="mediumIL">
      <uap:VisualElements DisplayName="Inkrail" Description="Offline, typewriter-inspired writing app"
        BackgroundColor="transparent" Square150x150Logo="MSIXAssets\Square150x150Logo.png"
        Square44x44Logo="MSIXAssets\Square44x44Logo.png" />
    </Application>
  </Applications>
</Package>
"@

$manifestPath = Join-Path $staging 'AppxManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
[xml]$manifestDoc = Get-Content -LiteralPath $manifestPath -Raw

$outputFile = Join-Path $outputDir "Inkrail_$($Version)_x64.msix"
Write-Host "Packaging with $($makeAppx.FullName)"
& $makeAppx.FullName pack /d $staging /p $outputFile /o
if ($LASTEXITCODE -ne 0) {
    throw "MakeAppx.exe failed with exit code $LASTEXITCODE."
}
Write-Host "Created: $outputFile"
Get-FileHash -LiteralPath $outputFile -Algorithm SHA256 | Format-List
Write-Host 'Unsigned package: submit in Partner Center MSIX product. Do not sideload without appropriate development signing.'
