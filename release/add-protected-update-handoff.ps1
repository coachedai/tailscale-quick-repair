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
        '$ProtectedUpdateMarkerPath = Join-Path $StateDir ''protected-update.json''' + [Environment]::NewLine +
        '$RestartRegistryPath = ''HKCU:\Software\TailscaleQuickRepair''' + [Environment]::NewLine +
        '$RestartRegistryName = ''PendingRestartVersionCode''') 'Setup path'
}

$functionBlock = @'
    function Invoke-PendingProtectedUpdate {
        param([scriptblock]$StartProcess)

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

            $requesterSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            if ([string]::IsNullOrWhiteSpace($requesterSid) -or $requesterSid -notmatch '^S-1-[0-9-]+            $psi.UseShellExecute = $true
            if ($StartProcess) {
                $process = & $StartProcess $psi
            }
            else {
                $process = [System.Diagnostics.Process]::Start($psi)
            }

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

    function Acknowledge-ProtectedRestart {
        try {
            if (-not (Test-Path -LiteralPath $RestartRegistryPath)) {
                return $false
            }

            $values = Get-ItemProperty -LiteralPath $RestartRegistryPath -Name $RestartRegistryName -ErrorAction SilentlyContinue
            if (-not $values -or $null -eq $values.$RestartRegistryName) {
                return $false
            }

            $pending = $values.$RestartRegistryName
            $validType = $pending -is [long] -or $pending -is [int]
            if (-not $validType -or [int64]$pending -ne $ProductVersionCode) {
                $UpdateStatusText.Text = 'Restart confirmation needs attention'
                $UpdateStatusText.Foreground = Get-Brush 'Amber'
                $UpdateDetailText.Text = 'Quick Repair is running, but the saved restart confirmation does not match this version.'
                $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                return $false
            }

            Remove-ItemProperty -LiteralPath $RestartRegistryPath -Name $RestartRegistryName -ErrorAction Stop
            $remaining = Get-ItemProperty -LiteralPath $RestartRegistryPath -Name $RestartRegistryName -ErrorAction SilentlyContinue
            if ($remaining -and $null -ne $remaining.$RestartRegistryName) {
                throw 'Restart confirmation could not be cleared.'
            }

            if (Get-Command Write-LocalHistoryEvent -ErrorAction SilentlyContinue) {
                Write-LocalHistoryEvent 'update_installed'
            }
            if (Get-Command Request-SmartNotification -ErrorAction SilentlyContinue) {
                [void](Request-SmartNotification 'update_installed' ([DateTime]::UtcNow.ToString('o')))
            }

            $UpdateStatusText.Text = "Updated successfully · $ProductVersion"
            $UpdateStatusText.Foreground = Get-Brush 'Green'
            $UpdateDetailText.Text = 'The protected update finished and Quick Repair restarted normally.'
            $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
            return $true
        }
        catch {
            $UpdateStatusText.Text = 'Restart confirmation needs attention'
            $UpdateStatusText.Foreground = Get-Brush 'Amber'
            $UpdateDetailText.Text = 'Quick Repair is running, but restart confirmation could not be completed.'
            $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
            return $false
        }
    }

'@

if($text -notmatch [regex]::Escape('function Invoke-PendingProtectedUpdate')) {
    Replace-ExactOnce '    function Start-UpdateInstall {' ($functionBlock + '    function Start-UpdateInstall {') 'update install function'
}

$bridgeSuccess = @'
            if ([bool]$result.success) {
                Write-LocalHistoryEvent 'update_installed'
                [void](Request-SmartNotification 'update_installed' $notificationResultStamp)
                $UpdateStatusText.Text = "Updated successfully · $([string]$result.version)"
                $UpdateStatusText.Foreground = Get-Brush 'Green'
                $UpdateDetailText.Text = 'The verified update was installed and Quick Repair restarted normally.'
                $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
            }
'@
$bridgePending = @'
            if ([bool]$result.success) {
                if (Test-Path -LiteralPath $ProtectedUpdateMarkerPath) {
                    $UpdateStatusText.Text = 'Update downloaded · finishing setup'
                    $UpdateStatusText.Foreground = Get-Brush 'Blue'
                    $UpdateDetailText.Text = 'Windows approval is needed to finish the protected part of this update.'
                    $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                }
                else {
                    Write-LocalHistoryEvent 'update_installed'
                    [void](Request-SmartNotification 'update_installed' $notificationResultStamp)
                    $UpdateStatusText.Text = "Updated successfully · $([string]$result.version)"
                    $UpdateStatusText.Foreground = Get-Brush 'Green'
                    $UpdateDetailText.Text = 'The verified update was installed and Quick Repair restarted normally.'
                    $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                }
            }
'@
Replace-ExactOnce $bridgeSuccess $bridgePending 'protected handoff update-result presentation'

$startup = @'
                Show-UpdateResult
                [void](Get-ActiveOperationLock -RecoverStale)
'@
$startupNew = @'
                Show-UpdateResult
                [void](Get-ActiveOperationLock -RecoverStale)
                if (Invoke-PendingProtectedUpdate) {
                    return
                }
                [void](Acknowledge-ProtectedRestart)
'@
if($text -notmatch [regex]::Escape('[void](Invoke-PendingProtectedUpdate)')) {
    Replace-ExactOnce $startup $startupNew 'startup protected update handoff'
}

foreach($required in @(
    '$ProtectedUpdateMarkerPath',
    '$RestartRegistryPath',
    '$RestartRegistryName',
    'function Invoke-PendingProtectedUpdate',
    'function Acknowledge-ProtectedRestart',
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
) {
                throw 'The Windows account could not be verified.'
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $SetupHostPath
            $psi.Arguments = '--upgrade --requester-sid "' + $requesterSid + '"'
            $psi.Verb = 'runas'
            $psi.UseShellExecute = $true
            if ($StartProcess) {
                $process = & $StartProcess $psi
            }
            else {
                $process = [System.Diagnostics.Process]::Start($psi)
            }

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

    function Acknowledge-ProtectedRestart {
        try {
            if (-not (Test-Path -LiteralPath $RestartRegistryPath)) {
                return $false
            }

            $values = Get-ItemProperty -LiteralPath $RestartRegistryPath -Name $RestartRegistryName -ErrorAction SilentlyContinue
            if (-not $values -or $null -eq $values.$RestartRegistryName) {
                return $false
            }

            $pending = $values.$RestartRegistryName
            $validType = $pending -is [long] -or $pending -is [int]
            if (-not $validType -or [int64]$pending -ne $ProductVersionCode) {
                $UpdateStatusText.Text = 'Restart confirmation needs attention'
                $UpdateStatusText.Foreground = Get-Brush 'Amber'
                $UpdateDetailText.Text = 'Quick Repair is running, but the saved restart confirmation does not match this version.'
                $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                return $false
            }

            Remove-ItemProperty -LiteralPath $RestartRegistryPath -Name $RestartRegistryName -ErrorAction Stop
            $remaining = Get-ItemProperty -LiteralPath $RestartRegistryPath -Name $RestartRegistryName -ErrorAction SilentlyContinue
            if ($remaining -and $null -ne $remaining.$RestartRegistryName) {
                throw 'Restart confirmation could not be cleared.'
            }

            if (Get-Command Write-LocalHistoryEvent -ErrorAction SilentlyContinue) {
                Write-LocalHistoryEvent 'update_installed'
            }
            if (Get-Command Request-SmartNotification -ErrorAction SilentlyContinue) {
                [void](Request-SmartNotification 'update_installed' ([DateTime]::UtcNow.ToString('o')))
            }

            $UpdateStatusText.Text = "Updated successfully · $ProductVersion"
            $UpdateStatusText.Foreground = Get-Brush 'Green'
            $UpdateDetailText.Text = 'The protected update finished and Quick Repair restarted normally.'
            $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
            return $true
        }
        catch {
            $UpdateStatusText.Text = 'Restart confirmation needs attention'
            $UpdateStatusText.Foreground = Get-Brush 'Amber'
            $UpdateDetailText.Text = 'Quick Repair is running, but restart confirmation could not be completed.'
            $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
            return $false
        }
    }

'@

if($text -notmatch [regex]::Escape('function Invoke-PendingProtectedUpdate')) {
    Replace-ExactOnce '    function Start-UpdateInstall {' ($functionBlock + '    function Start-UpdateInstall {') 'update install function'
}

$bridgeSuccess = @'
            if ([bool]$result.success) {
                Write-LocalHistoryEvent 'update_installed'
                [void](Request-SmartNotification 'update_installed' $notificationResultStamp)
                $UpdateStatusText.Text = "Updated successfully · $([string]$result.version)"
                $UpdateStatusText.Foreground = Get-Brush 'Green'
                $UpdateDetailText.Text = 'The verified update was installed and Quick Repair restarted normally.'
                $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
            }
'@
$bridgePending = @'
            if ([bool]$result.success) {
                if (Test-Path -LiteralPath $ProtectedUpdateMarkerPath) {
                    $UpdateStatusText.Text = 'Update downloaded · finishing setup'
                    $UpdateStatusText.Foreground = Get-Brush 'Blue'
                    $UpdateDetailText.Text = 'Windows approval is needed to finish the protected part of this update.'
                    $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                }
                else {
                    Write-LocalHistoryEvent 'update_installed'
                    [void](Request-SmartNotification 'update_installed' $notificationResultStamp)
                    $UpdateStatusText.Text = "Updated successfully · $([string]$result.version)"
                    $UpdateStatusText.Foreground = Get-Brush 'Green'
                    $UpdateDetailText.Text = 'The verified update was installed and Quick Repair restarted normally.'
                    $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                }
            }
'@
Replace-ExactOnce $bridgeSuccess $bridgePending 'protected handoff update-result presentation'

$startup = @'
                Show-UpdateResult
                [void](Get-ActiveOperationLock -RecoverStale)
'@
$startupNew = @'
                Show-UpdateResult
                [void](Get-ActiveOperationLock -RecoverStale)
                if (Invoke-PendingProtectedUpdate) {
                    return
                }
                [void](Acknowledge-ProtectedRestart)
'@
if($text -notmatch [regex]::Escape('[void](Invoke-PendingProtectedUpdate)')) {
    Replace-ExactOnce $startup $startupNew 'startup protected update handoff'
}

foreach($required in @(
    '$ProtectedUpdateMarkerPath',
    '$RestartRegistryPath',
    '$RestartRegistryName',
    'function Invoke-PendingProtectedUpdate',
    'function Acknowledge-ProtectedRestart',
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
