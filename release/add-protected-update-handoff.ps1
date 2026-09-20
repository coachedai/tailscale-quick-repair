param([Parameter(Mandatory=$true)][string]$Path)

$ErrorActionPreference = 'Stop'
$text = [IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)

function Replace-ExactOnce {
    param([string]$Find,[string]$Replace,[string]$Description)
    $first = $script:text.IndexOf($Find,[StringComparison]::Ordinal)
    if($first -lt 0 -or $script:text.IndexOf($Find,$first+$Find.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Expected one $Description marker."
    }
    $script:text = $script:text.Remove($first,$Find.Length).Insert($first,$Replace)
}

if($text -notmatch '(?m)^\$ProtectedUpdateMarkerPath\s*=') {
    $setupLine = '$SetupHostPath = Join-Path $StateDir ''TailscaleQuickRepairSetup.exe'''
    Replace-ExactOnce $setupLine ($setupLine + [Environment]::NewLine +
        '$ProtectedUpdateMarkerPath = Join-Path $StateDir ''protected-update.json''') 'Setup path'
}

$functionBlock = @'
    function Invoke-PendingProtectedUpdate {
        if ($script:pendingProtectedUpdateStarted -or -not (Test-Path -LiteralPath $ProtectedUpdateMarkerPath)) {
            return $false
        }

        try {
            $marker = Get-Content -LiteralPath $ProtectedUpdateMarkerPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            $names = @($marker.PSObject.Properties.Name)
            $validCodeType = $marker.versionCode -is [int] -or $marker.versionCode -is [long]

            if (
                $names.Count -ne 2 -or
                'schema' -notin $names -or
                'versionCode' -notin $names -or
                $marker.schema -isnot [int] -or
                [int]$marker.schema -ne 1 -or
                -not $validCodeType -or
                [int64]$marker.versionCode -ne $ProductVersionCode
            ) {
                throw 'The protected update marker is invalid.'
            }

            if (-not (Test-Path -LiteralPath $SetupHostPath -PathType Leaf)) {
                throw 'The verified Setup component is missing.'
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $SetupHostPath
            $psi.Arguments = '--upgrade'
            $psi.UseShellExecute = $true
            $process = [System.Diagnostics.Process]::Start($psi)

            if (-not $process) {
                throw 'The protected update could not start.'
            }

            $script:pendingProtectedUpdateStarted = $true
            $script:allowFullExit = $true
            $global:TqrUiShutdownRequested = $true
            $UpdateStatusText.Text = 'Finishing protected update…'
            $UpdateStatusText.Foreground = Get-Brush 'Blue'
            $UpdateDetailText.Text = 'Approve the Windows prompt. Quick Repair will reopen when the update is complete.'
            $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible

            $window.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [Action]{ try { $window.Close() } catch {} }
            ) | Out-Null
            return $true
        }
        catch {
            $UpdateStatusText.Text = 'Protected update needs attention'
            $UpdateStatusText.Foreground = Get-Brush 'Amber'
            $UpdateDetailText.Text = 'The protected part of the update was not started. Nothing protected was changed.'
            $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
            return $false
        }
    }

'@

if($text -notmatch [regex]::Escape('function Invoke-PendingProtectedUpdate')) {
    Replace-ExactOnce '    function Start-UpdateInstall {' ($functionBlock + '    function Start-UpdateInstall {') 'update install function'
}

$startup = @'
                Show-UpdateResult
                [void](Get-ActiveOperationLock -RecoverStale)
'@
$startupNew = @'
                Show-UpdateResult
                [void](Get-ActiveOperationLock -RecoverStale)
                [void](Invoke-PendingProtectedUpdate)
'@
if($text -notmatch [regex]::Escape('[void](Invoke-PendingProtectedUpdate)')) {
    Replace-ExactOnce $startup $startupNew 'startup protected update handoff'
}

foreach($required in @(
    '$ProtectedUpdateMarkerPath',
    'function Invoke-PendingProtectedUpdate',
    "$psi.Arguments = '--upgrade'",
    'Finishing protected update…'
)) {
    if($text -notmatch [regex]::Escape($required)) {
        throw "Protected update handoff verification failed: $required"
    }
}

[void][scriptblock]::Create($text)
[IO.File]::WriteAllText($Path,$text,(New-Object Text.UTF8Encoding($true)))
Write-Host 'Protected update handoff routing applied.'
