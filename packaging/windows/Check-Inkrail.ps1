# Optional Windows-native smoke test for an extracted portable build.
# No administrator rights, network downloads, Go, Python or Node needed.
# Writes only to its own new temporary profile; does not open your real library.
[CmdletBinding()]
param([string]$Executable = (Join-Path $PSScriptRoot 'Inkrail.exe'))
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$testProfile = Join-Path ([IO.Path]::GetTempPath()) ('Inkrail-QA-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testProfile) | Out-Null
$library = Join-Path $testProfile 'Custom Library'
$letters = Join-Path $library 'Letters'
New-Item -ItemType Directory -Path $letters, (Join-Path $library 'Recently Deleted') | Out-Null
$id = [guid]::NewGuid().ToString().ToUpperInvariant()
$letterPath = Join-Path $letters "$id.json"
$preferencesPath = Join-Path $testProfile 'preferences.json'
$utf8 = [Text.UTF8Encoding]::new($false)
$legacyText = 'Styled writing from the previous version.'
$legacyLetter = @{
    id = $id; createdAt = '2025-04-01T12:00:00Z'; modifiedAt = '2025-04-01T12:30:00Z'
    privateTitle = 'Original title'; text = $legacyText
    formatting = @(@{location = 0; length = 6; emphasis = 1})
}
$legacySettings = @{
    libraryLocation = $library; selectedID = $id
    preferences = @{nightMode = $true; soundEnabled = $false; typewriterSound = 'office'; wornInk = $false}
}
[IO.File]::WriteAllText($letterPath, ($legacyLetter | ConvertTo-Json -Depth 5), $utf8)
[IO.File]::WriteAllText($preferencesPath, ($legacySettings | ConvertTo-Json -Depth 5), $utf8)
$needle = 'Inkrail Windows smoke ' + [guid]::NewGuid().ToString('N')
$script:proc = $null
$script:socket = $null
$script:seq = 0
function Get-TestPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    try { $listener.Start(); return $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}
function Call-CDP([string]$method, $arguments) {
    $script:seq++
    $id = $script:seq
    $ct = New-Object Threading.CancellationTokenSource
    $ct.CancelAfter(10000)
    try {
        $json = @{id=$id;method=$method;params=$arguments} | ConvertTo-Json -Depth 10 -Compress
        $payload = [Text.Encoding]::UTF8.GetBytes($json)
        $segment = [ArraySegment[byte]]::new($payload)
        $script:socket.SendAsync($segment,[Net.WebSockets.WebSocketMessageType]::Text,$true,$ct.Token).GetAwaiter().GetResult() | Out-Null
        while ($true) {
            $buf = New-Object byte[] 16384
            $mem = New-Object IO.MemoryStream
            try {
                do {
                    $part = $script:socket.ReceiveAsync([ArraySegment[byte]]::new($buf),$ct.Token).GetAwaiter().GetResult()
                    if ($part.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'WebView2 closed its test connection.' }
                    $mem.Write($buf,0,$part.Count)
                } while (-not $part.EndOfMessage)
                $msg = [Text.Encoding]::UTF8.GetString($mem.ToArray()) | ConvertFrom-Json
            } finally { $mem.Dispose() }
            if ($msg.id -eq $id) {
                if ($msg.error) { throw $msg.error.message }
                return $msg.result
            }
        }
    } finally { $ct.Dispose() }
}
function Eval-Desk([string]$expression) {
    $result = Call-CDP 'Runtime.evaluate' @{expression=$expression;returnByValue=$true}
    if ($result.exceptionDetails) { throw ('Desk evaluation failed: ' + $result.exceptionDetails.text) }
    return $result.result.value
}
function Wait-Desk([string]$expression) {
    $deadline = (Get-Date).AddSeconds(10)
    do {
        if (Eval-Desk $expression) { return }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    throw "The desk did not reach the expected state: $expression"
}
function Click-Desk([string]$selector) {
    $element = 'document.querySelector(' + (ConvertTo-Json $selector -Compress) + ')'
    Wait-Desk "$element && !$element.disabled"
    $null = Eval-Desk "$element.click()"
}
function Start-Desk([string]$profileDirectory = $testProfile) {
    $port = Get-TestPort
    $script:proc = Start-Process -FilePath $exe -ArgumentList ('-data "' + $profileDirectory + '" -qa-port ' + $port) -PassThru
    $deadline = (Get-Date).AddSeconds(35)
    $target=$null
    while ((Get-Date) -lt $deadline -and -not $script:proc.HasExited) {
        try {
            $entries = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/json/list") -TimeoutSec 2
            $target = $entries | Where-Object { $_.type -eq 'page' -and $_.url -like 'https://inkrail.invalid/index.html*' } | Select-Object -First 1
            if ($target) { break }
        } catch { Start-Sleep -Milliseconds 120 }
        Start-Sleep -Milliseconds 80
    }
    if (-not $target) { throw 'Inkrail did not start its test WebView2 window. Check the runtime and extract the complete ZIP.' }
    $endpoint=[uri]$target.webSocketDebuggerUrl
    if ($endpoint.Scheme -ne 'ws' -or -not $endpoint.IsLoopback -or $endpoint.Port -ne $port) { throw 'Unexpected native test endpoint.' }
    $script:socket = New-Object Net.WebSockets.ClientWebSocket
    $ct=New-Object Threading.CancellationTokenSource
    try {
        $ct.CancelAfter(10000)
        $script:socket.ConnectAsync($endpoint,$ct.Token).GetAwaiter().GetResult() | Out-Null
    } finally { $ct.Dispose() }
    do {
        if ((Eval-Desk "document.documentElement.dataset.ready==='true'")) { return }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    throw 'The window opened but the editor did not finish starting.'
}
function Close-Desk {
    $script:proc.Refresh()
    if (-not $script:proc.CloseMainWindow()) { throw 'The OS did not find the Inkrail test window.' }
    if (-not $script:proc.WaitForExit(12000)) { throw 'Inkrail did not finish saving and close in time.' }
    if ($script:proc.ExitCode -ne 0) { throw ('Inkrail exited with code ' + $script:proc.ExitCode) }
    $script:socket.Dispose(); $script:socket=$null
    $script:proc.Dispose(); $script:proc=$null
}
try {
    Start-Desk
    Wait-Desk "document.querySelector('.ink-editor').textContent === '$legacyText'"
    Wait-Desk "document.querySelector('.ink-editor .ink-bold')?.textContent === 'Styled'"
    Wait-Desk "document.querySelector('[data-action=night]').getAttribute('aria-pressed') === 'true'"
    Click-Desk '[data-action=night]'
    Click-Desk '[data-action=library]'
    Click-Desk 'dialog[open] [aria-label="Rename Original title"]'
    $null = Eval-Desk "document.querySelector('.ip-title-input').value = 'Renamed letter'"
    Click-Desk 'dialog[open] button[type=submit]'
    Wait-Desk "!document.querySelector('.ip-subdialog').open"
    Click-Desk 'dialog[open] [aria-label="Delete Renamed letter"]'
    Click-Desk 'dialog[open] button[type=submit]'
    Wait-Desk "!document.querySelector('.ip-subdialog').open"
    if (Test-Path -LiteralPath $letterPath) { throw 'Deleting a letter left it in Letters.' }
    Click-Desk 'dialog[open] .ip-library-footer > button:first-child'
    Click-Desk 'dialog[open] [aria-label="Restore Renamed letter"]'
    Wait-Desk "!document.querySelector('[data-row-action=restore]')"
    Click-Desk 'dialog[open] .ip-library-footer > button:first-child'
    Click-Desk 'dialog[open] [aria-label="Open Renamed letter"]'
    Wait-Desk "!document.querySelector('dialog[open]')"
    Wait-Desk "document.querySelector('.ink-editor').textContent === '$legacyText'"
    $null = Eval-Desk "document.querySelector('.ink-editor').focus(); getSelection().selectAllChildren(document.querySelector('.ink-editor')); getSelection().collapseToEnd(); true"
    $null=Call-CDP 'Input.insertText' @{text=$needle}
    if (-not (Eval-Desk ("document.querySelector('.ink-editor').textContent.includes('" + $needle + "')"))) { throw 'Writing did not appear in the editor.' }
    Close-Desk
    $letter = [IO.File]::ReadAllText($letterPath) | ConvertFrom-Json
    if ($letter.text -ne ($legacyText + $needle) -or $letter.privateTitle -ne 'Renamed letter' -or
        $letter.formatting[0].location -ne 0 -or $letter.formatting[0].length -ne 6 -or $letter.formatting[0].emphasis -ne 1) {
        throw 'The restored letter lost its title, original formatting, or last keystrokes.'
    }
    $saved = [IO.File]::ReadAllText($preferencesPath) | ConvertFrom-Json
    if ($saved.libraryLocation -ne $library -or $saved.selectedID -ne $id -or $saved.preferences.nightMode -ne $false -or
        $saved.preferences.soundEnabled -ne $false -or $saved.preferences.typewriterSound -ne 'royal') {
        throw 'Settings or the selected custom-library letter were lost during the upgrade.'
    }
    Start-Desk
    Wait-Desk "document.querySelector('.ink-editor').textContent === '$legacyText$needle'"
    Wait-Desk "document.querySelector('.ink-editor .ink-bold')?.textContent === 'Styled'"
    Wait-Desk "document.querySelector('[data-action=night]').getAttribute('aria-pressed') === 'false'"
    Close-Desk

    $freshProfile = Join-Path $testProfile 'First launch'
    [IO.Directory]::CreateDirectory($freshProfile) | Out-Null
    Start-Desk $freshProfile
    $null = Eval-Desk "document.querySelector('.ink-editor').focus(); true"
    $null = Call-CDP 'Input.insertText' @{text=$needle}
    Close-Desk
    $freshLetters = @(Get-ChildItem -LiteralPath (Join-Path $freshProfile 'Library\Letters') -Filter '*.json')
    if ($freshLetters.Count -ne 1) { throw 'Expected one letter in the new default library.' }
    $freshLetter = [IO.File]::ReadAllText($freshLetters[0].FullName) | ConvertFrom-Json
    if (-not $freshLetter.text.Contains($needle)) { throw 'First launch did not save the writing.' }
    Write-Output 'PASS: first launch, legacy custom library, preferences, formatting, rename, trash, restore, typing, close-time save, and reopen.'
    Write-Output ("Disposable profile (safe to remove after inspection): " + $testProfile)
} finally {
    if ($script:socket) { $script:socket.Dispose() }
    if ($script:proc -and -not $script:proc.HasExited) {
        # This process was launched with a fresh, isolated test profile.
        $script:proc.Kill(); $script:proc.WaitForExit()
    }
}
