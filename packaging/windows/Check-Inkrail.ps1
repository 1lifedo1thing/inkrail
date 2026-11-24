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
$savedDeskChoices = @{
    paperMotion = 'sheet'; paperStartPosition = 'top'; textureStrength = 0.55
    paperEmbossing = 'none'; embossingDepth = 0.45
    mechanismStyle = 'classic'; matchRailToStyle = $false
    soundVolume = 0.30; lampIntensity = 0.82; lampWarmth = 0.65
}
$legacySettings = @{
    libraryLocation = $library; selectedID = $id
    preferences = $savedDeskChoices + @{nightMode = $true; soundEnabled = $false; typewriterSound = 'office'; wornInk = $false}
}
[IO.File]::WriteAllText($letterPath, ($legacyLetter | ConvertTo-Json -Depth 5), $utf8)
[IO.File]::WriteAllText($preferencesPath, ($legacySettings | ConvertTo-Json -Depth 5), $utf8)
$needle = 'Inkrail Windows smoke ' + [guid]::NewGuid().ToString('N')
$script:proc = $null
$script:socket = $null
$script:seq = 0
function Assert-Preferences($actual, [hashtable]$expected) {
    foreach ($key in $expected.Keys) {
        if ($actual.$key -ne $expected[$key]) {
            throw "Expected $key to be '$($expected[$key])', got '$($actual.$key)'."
        }
    }
}
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
function Eval-Desk([string]$expression, [switch]$AwaitPromise) {
    $result = Call-CDP 'Runtime.evaluate' @{expression=$expression;returnByValue=$true;awaitPromise=$AwaitPromise.IsPresent}
    if ($result.exceptionDetails) {
        $details = $result.exceptionDetails
        $reason = $details.exception.description
        if (-not $reason) { $reason = $details.exception.value }
        if (-not $reason) { $reason = $details.text }
        throw "Desk evaluation failed for [$expression]: $reason"
    }
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
    $selectorJson = ConvertTo-Json $selector -Compress
    Wait-Desk @"
(() => {
    const button = document.querySelector($selectorJson);
    if (!button || button.disabled) return false;
    button.click();
    return true;
})()
"@
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
        if ((Eval-Desk "document.documentElement?.dataset.ready === 'true'")) { return }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    throw 'The window opened but the editor did not finish starting.'
}
function Request-DeskClose {
    $script:proc.Refresh()
    if (-not $script:proc.CloseMainWindow()) { throw 'The OS did not find the Inkrail test window.' }
}
function Wait-DeskExit {
    if (-not $script:proc.WaitForExit(12000)) { throw 'Inkrail did not finish saving and close in time.' }
    if ($script:proc.ExitCode -ne 0) { throw ('Inkrail exited with code ' + $script:proc.ExitCode) }
    $script:socket.Dispose(); $script:socket=$null
    $script:proc.Dispose(); $script:proc=$null
}
function Close-Desk {
    Request-DeskClose
    Wait-DeskExit
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
    Assert-Preferences $saved.preferences $savedDeskChoices
    if ($saved.libraryLocation -ne $library -or $saved.selectedID -ne $id -or $saved.preferences.nightMode -ne $false -or
        $saved.preferences.soundEnabled -ne $false -or $saved.preferences.typewriterSound -ne 'royal') {
        throw 'Settings or the selected custom-library letter were lost during the upgrade.'
    }
    Start-Desk
    Wait-Desk "document.querySelector('.ink-editor').textContent === '$legacyText$needle'"
    Wait-Desk "document.querySelector('.ink-editor .ink-bold')?.textContent === 'Styled'"
    Wait-Desk "document.querySelector('[data-action=night]').getAttribute('aria-pressed') === 'false'"

    # Keep one letter in conflict while autosave writes a second letter and the selection.
    $originalBytes = [IO.File]::ReadAllBytes($letterPath)
    $external = [IO.File]::ReadAllText($letterPath) | ConvertFrom-Json
    $external.text = 'Edited outside Inkrail'
    [IO.File]::WriteAllText($letterPath, ($external | ConvertTo-Json -Depth 5), $utf8)
    $null = Eval-Desk "const editor = document.querySelector('.ink-editor'); editor.focus(); getSelection().selectAllChildren(editor); true"
    $null = Call-CDP 'Input.insertText' @{text='Pending local edit'}
    Wait-Desk "document.querySelector('#notice[open]')?.textContent.includes('Renamed letter')"
    Click-Desk '#notice-ok'
    Click-Desk '[data-action=new]'
    Wait-Desk "document.querySelector('.ink-editor').textContent === ''"
    $null = Eval-Desk "document.querySelector('.ink-editor').focus(); true"
    $null = Call-CDP 'Input.insertText' @{text='Independent letter'}
    $deadline = (Get-Date).AddSeconds(10)
    do {
        $selected = ([IO.File]::ReadAllText($preferencesPath) | ConvertFrom-Json).selectedID
        $otherPath = Join-Path $letters "$selected.json"
        if ($selected -ne $id -and (Test-Path -LiteralPath $otherPath) -and
            ([IO.File]::ReadAllText($otherPath) | ConvertFrom-Json).text -eq 'Independent letter') { break }
        if ((Get-Date) -ge $deadline) { throw 'A conflict blocked autosave of another letter or its selection.' }
        Start-Sleep -Milliseconds 100
    } while ($true)
    if (([IO.File]::ReadAllText($letterPath) | ConvertFrom-Json).text -ne $external.text) {
        throw 'Autosave overwrote a conflicting letter.'
    }
    [IO.File]::WriteAllBytes($letterPath, $originalBytes)
    $null = Eval-Desk "window.dispatchEvent(new Event('inkrail-flush'))"
    Wait-Desk "!document.querySelector('.s-dot.dirty')"
    if (([IO.File]::ReadAllText($letterPath) | ConvertFrom-Json).text -ne 'Pending local edit') {
        throw 'Autosave dropped the conflicted edit instead of retrying it.'
    }

    Click-Desk '[data-action=night]'
    Click-Desk '[data-action=settings]'
    Click-Desk '[data-tab=machine]'
    Click-Desk '[data-choice-val=brushedSteel]'
    Wait-Desk @'
(() => {
    const art = '.ink-desk__capsule[data-style=brushedSteel] .ink-desk__capsule-art';
    const live = document.querySelector('#desk ' + art);
    if (!live?.childElementCount) return false;
    const liveStyle = getComputedStyle(live);
    return ['[data-choice-val=brushedSteel]', '.ip-preview-machine'].every(selector => {
        const preview = document.querySelector(selector + ' ' + art);
        if (!preview || preview.innerHTML !== live.innerHTML) return false;
        const capsule = preview.closest('.ink-desk__capsule');
        const housing = capsule.querySelector('.ink-desk__housing').getBoundingClientRect();
        const hammer = capsule.querySelector('.ink-desk__hammer').getBoundingClientRect();
        const frame = preview.closest('.ip-preview').getBoundingClientRect();
        const artwork = preview.getBoundingClientRect();
        const previewStyle = getComputedStyle(preview);
        return artwork.width > 0 && Math.abs(artwork.width - housing.width) < 1 && Math.abs(artwork.height - housing.height) < 1 &&
            hammer.top >= frame.top && housing.bottom <= frame.bottom && housing.left >= frame.left && housing.right <= frame.right &&
            capsule.querySelector('.ink-desk__emitter').getClientRects().length > 0 &&
            previewStyle.fill === liveStyle.fill && previewStyle.stroke === liveStyle.stroke;
    });
})()
'@
    Click-Desk 'dialog[open] .ip-header button'
    Close-Desk

    $freshProfile = Join-Path $testProfile 'First launch'
    [IO.Directory]::CreateDirectory($freshProfile) | Out-Null
    Start-Desk $freshProfile

    # Hold the actual export command before Save As. A failed preparation after
    # an OS close request must return the writer to the desk with the error.
    $null = Eval-Desk @'
Object.defineProperty(document.fonts, 'ready', {
    configurable: true,
    get() {
        return new Promise((_, reject) => {
            window.failTestPrint = () => {
                delete document.fonts.ready;
                reject(new Error('PDF preparation failed in the smoke test.'));
            };
        });
    }
}); true
'@
    Click-Desk '[data-action=export]'
    Click-Desk '[data-command=exportPDF]'
    Wait-Desk "typeof window.failTestPrint === 'function'"
    Request-DeskClose
    # Wait for a round trip through the native UI thread after posting WM_CLOSE.
    $bridge = "import(location.origin + '/bridge.js')"
    $null = Eval-Desk "$bridge.then(({call}) => call('windowDirty', false))" -AwaitPromise
    $null = Eval-Desk 'window.failTestPrint(); true'
    Wait-Desk "document.querySelector('#notice').open && document.querySelector('#notice-text').textContent.includes('PDF preparation failed in the smoke test.') && !document.querySelector('#letter-print')"
    Click-Desk '#notice-ok'

    # Exercise the host's success path with a controlled completion. This keeps
    # the test unattended and holds the export longer than the save watchdog.
    $null = Eval-Desk "window.addEventListener('inkrail-close-request', () => { window.testCloseFlushStarted = true; }); true"
    $began = Eval-Desk "$bridge.then(({call}) => call('beginPdfExport'))" -AwaitPromise
    if (-not $began) { throw 'The writer could not start another PDF export after the failed preparation.' }
    Request-DeskClose
    if ($script:proc.WaitForExit(13000)) { throw 'Inkrail closed while a PDF export was still active.' }
    if (Eval-Desk 'window.testCloseFlushStarted === true') { throw 'The close watchdog started before PDF completion.' }
    $null = Eval-Desk "document.querySelector('.ink-editor').focus(); true"
    $null = Call-CDP 'Input.insertText' @{text=$needle}
    $null = Eval-Desk "void $bridge.then(({call}) => call('endPdfExport', true)); true"
    Wait-DeskExit
    $freshLetters = @(Get-ChildItem -LiteralPath (Join-Path $freshProfile 'Library\Letters') -Filter '*.json')
    if ($freshLetters.Count -ne 1) { throw 'Expected one letter in the new default library.' }
    $freshLetter = [IO.File]::ReadAllText($freshLetters[0].FullName) | ConvertFrom-Json
    if (-not $freshLetter.text.Contains($needle)) { throw 'The deferred close did not save the final edit.' }
    $freshSettings = [IO.File]::ReadAllText((Join-Path $freshProfile 'preferences.json')) | ConvertFrom-Json
    Assert-Preferences $freshSettings.preferences @{
        paperMotion = 'roll'; paperStartPosition = 'bottom'; paperTexture = 'classic'; textureStrength = 0.70
        paperEmbossing = 'makerMark'; embossingDepth = 0.70
        mechanismStyle = 'walnut'; matchRailToStyle = $true
        soundVolume = 0.55; nightMode = $false; lampIntensity = 0.85; lampWarmth = 0.55
    }
    Write-Output 'PASS: first launch, legacy library, preferences, machine previews, formatting, rename, trash, restore, independent autosaves, PDF close handling, and reopen.'
    Write-Output ("Disposable profile (safe to remove after inspection): " + $testProfile)
} finally {
    if ($script:socket) { $script:socket.Dispose() }
    if ($script:proc -and -not $script:proc.HasExited) {
        # This process was launched with a fresh, isolated test profile.
        $script:proc.Kill(); $script:proc.WaitForExit()
    }
}
