[CmdletBinding()]
param([Parameter(Mandatory)][string]$Archive)

$ErrorActionPreference = 'Stop'
$work = Join-Path ([IO.Path]::GetTempPath()) ('Inkrail-editor-' + [guid]::NewGuid().ToString('N'))
try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $work
    $app = @(Get-ChildItem -LiteralPath $work -Filter Inkrail.exe -File -Recurse)
    if ($app.Count -ne 1) { throw 'Expected one Inkrail executable in the portable ZIP.' }
    $page = Join-Path $app[0].DirectoryName 'check-editor.html'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'check-editor.html') -Destination $page
    $browser = @(
        ${env:ProgramFiles(x86)}, $env:ProgramFiles | Where-Object { $_ } | ForEach-Object {
            Join-Path $_ 'Microsoft\Edge\Application\msedge.exe'
        } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    ) | Select-Object -First 1
    if (-not $browser) { throw 'Microsoft Edge was not found on this runner.' }
    $profile = Join-Path $work 'browser-profile'
    $uri = [uri]::new($page).AbsoluteUri
    $dom = & $browser --headless --disable-gpu --no-first-run --allow-file-access-from-files "--user-data-dir=$profile" --dump-dom $uri | Out-String
    if ($LASTEXITCODE -ne 0 -or $dom -notmatch '<pre id="result">PASS</pre>') {
        throw "Packaged editor regression failed. $dom"
    }
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
