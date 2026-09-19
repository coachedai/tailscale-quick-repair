"""One-shot source migration, run only on the isolated 3.4.2 development branch.
No release is published here. Every edit must match its reviewed source anchor.
"""
from pathlib import Path
import json
import os
import subprocess

EXPECTED = 'coachedai/tailscale-quick-repair'
BRANCH = 'fix/3.4.2-package-and-runtime-guards'
root = Path(__file__).resolve().parents[1]
if os.environ.get('GITHUB_REPOSITORY') != EXPECTED or os.environ.get('GITHUB_REF_NAME') != BRANCH:
    raise SystemExit('Wrong repository or branch; refusing source preparation.')
origin = subprocess.check_output(['git', '-C', str(root), 'remote', 'get-url', 'origin'], text=True).strip()
if origin not in ('https://github.com/' + EXPECTED, 'https://github.com/' + EXPECTED + '.git'):
    raise SystemExit('Unexpected repository origin.')
if json.loads((root / 'version.json').read_text())['version'] != '3.0.0-phase3.4.1':
    raise SystemExit('Source preparation only accepts the reviewed 3.4.1 baseline.')
files = {}
def read(path):
    if path not in files:
        files[path] = (root / path).read_text(encoding='utf-8-sig')
    return files[path]
def replace(path, old, new):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one source anchor, got {count}: {old[:100]!r}')
    files[path] = text.replace(old, new, 1)
def section(path, begin, end, new):
    text = read(path)
    if text.count(begin) != 1 or text.count(end) != 1:
        raise RuntimeError(f'{path}: ambiguous section anchors')
    a, b = text.index(begin), text.index(end)
    if b <= a:
        raise RuntimeError('Invalid section ordering')
    files[path] = text[:a] + new + text[b:]

# Compile the same coordinator implementation into both standalone native hosts.
wrappers = '''    private static Tqr.OperationLease operationLease;

    private static bool TryAcquireOperationLock(string kind)
    {
        operationLease = Tqr.OperationGate.TryAcquire(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TailscaleQuickRepair"), kind);
        return operationLease != null;
    }

    private static void ReleaseOperationLock()
    {
        if (operationLease != null)
        {
            operationLease.Dispose();
            operationLease = null;
        }
    }

'''
for path in ('src/native/UpdaterHost.cs', 'src/native/PublicSetupHost.cs'):
    section(path, '    private static string GetOperationLockPath()', '    [STAThread]', wrappers)

ui = 'src/app/Tailscale-Repair-UI.ps1'
replace(ui, "$OperationLockPath = Join-Path $StateDir 'operation.lock'", "$OperationLockPath = Join-Path $StateDir 'operation.lock'\n$OperationsLibraryPath = Join-Path $StateDir 'TailscaleQuickRepair.Operations.dll'")
section(ui, '    function Get-ActiveOperationLock {', '    function Update-AutoRepairStatus {', '''    function Initialize-OperationGate {
        if (-not ('Tqr.OperationGate' -as [type])) {
            Add-Type -Path $OperationsLibraryPath -ErrorAction Stop
        }
    }

    function Get-ActiveOperationLock {
        param([switch]$RecoverStale)
        try {
            Initialize-OperationGate
            return [Tqr.OperationGate]::Inspect($StateDir)
        }
        catch {
            # Inspection never deletes a marker or treats an unreadable owner as idle.
            return [pscustomobject]@{ kind = 'operation ownership verification'; ownerPid = 0 }
        }
    }

    function Acquire-UiOperationLock {
        param([Parameter(Mandatory=$true)][string]$Kind, [int]$Minutes = 3)
        try {
            Initialize-OperationGate
            if ($script:uiOperationLease) { return $false }
            $script:uiOperationLease = [Tqr.OperationGate]::TryAcquire($StateDir, $Kind)
            if (-not $script:uiOperationLease) { return $false }
            $script:uiOperationKind = $Kind
            return $true
        }
        catch { return $false }
    }

    function Release-UiOperationLock {
        param([string]$Kind = '')
        if (-not $script:uiOperationLease) { return }
        if ($Kind -and $script:uiOperationLease.Kind -ne $Kind) { return }
        $script:uiOperationLease.Dispose()
        $script:uiOperationLease = $null
        $script:uiOperationKind = ''
    }

''')
# The protected backend already reopens the client when needed. Do not mutate
# Tailscale or delete another run's state before the backend owns the operation.
replace(ui, "        Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue\n", "        # Preserve the previous result until the newly owned backend publishes.\n")
section(ui, "        $HeroDetail.Text = 'Checking the desktop client before starting the repair engine.'", "        try {\n            [void](Invoke-RepairTask)", "        $HeroDetail.Text = 'Starting the protected check.'\n\n")
replace(ui, "                $taskState = Get-RepairTaskState\n\n", """                $taskState = Get-RepairTaskState

                if ($taskState -notin @('Running','Queued') -and
                    -not $script:lastFreshStateUtc -and
                    ([DateTime]::UtcNow - $script:launchUtc).TotalSeconds -gt 4) {
                    $script:repairActive = $false
                    Set-Badge $HeroBadge $HeroBadgeText 'ATTENTION' 'warning'
                    $HeroTitle.Text = 'The check did not start'
                    $HeroDetail.Text = 'No new repair result was returned. Let any other Quick Repair operation finish, then try again.'
                    Set-ActionButton 'Try Again' 'repair' $true
                    return
                }

""")

backend = 'src/program/Repair-Backend.ps1'
section(backend, 'function Test-OperationOwnerAlive {', 'function Get-TailscaleCli {', '''function Acquire-OperationLock {
    param([string]$Kind = 'repair')
    try {
        if (-not ('Tqr.OperationGate' -as [type])) {
            Add-Type -Path (Join-Path $PSScriptRoot 'TailscaleQuickRepair.Operations.dll') -ErrorAction Stop
        }
        $script:repairOperationLease = [Tqr.OperationGate]::TryAcquire($StateDir, $Kind)
        return ($null -ne $script:repairOperationLease)
    }
    catch { return $false }
}

function Release-OperationLock {
    if ($script:repairOperationLease) {
        $script:repairOperationLease.Dispose()
        $script:repairOperationLease = $null
    }
}

''')
replace(backend, '''if (-not $operationAcquired) {
    Publish-State `
        'Quick Repair is busy' `
        'Another Quick Repair operation is already running. No repair actions were started.' `
        100 'warning' 'Complete' $true
    exit 0
}''', '''if (-not $operationAcquired) {
    # A rejected contender must not overwrite the current owner's result.
    exit 75
}''')
auto = 'src/program/Auto-Repair-Monitor.ps1'
section(auto, 'function Get-ActiveOperation {', 'function Get-Enabled {', '''function Get-ActiveOperation {
    try {
        if (-not ('Tqr.OperationGate' -as [type])) {
            Add-Type -Path (Join-Path $PSScriptRoot 'TailscaleQuickRepair.Operations.dll') -ErrorAction Stop
        }
        return [Tqr.OperationGate]::Inspect($AppDir)
    }
    catch {
        return [pscustomobject]@{ kind = 'operation ownership verification' }
    }
}

''')

build = 'release/build.ps1'
replace(build, "        ('\"{0}\"' -f $updaterEntry)\n", "        ('\"{0}\"' -f $updaterEntry)\n        ('\"{0}\"' -f (Join-Path $repo 'src\\native\\OperationGate.cs'))\n")
route = 'release/add-native-setup-routing.ps1'
replace(route, "    $args += ('\"{0}\"' -f (Join-Path $repo 'src\\native\\PublicSetupEntry.cs'))", "    $args += ('\"{0}\"' -f (Join-Path $repo 'src\\native\\PublicSetupEntry.cs'))\n    $args += ('\"{0}\"' -f (Join-Path $repo 'src\\native\\OperationGate.cs'))")
replace(route, "    $ui = [IO.File]::ReadAllText($uiPath,[Text.Encoding]::UTF8)", r'''    $operationsDll = Join-Path $appDir 'TailscaleQuickRepair.Operations.dll'
    $libraryArgs = @('/nologo','/target:library','/platform:anycpu','/optimize+',
        ('/out:"{0}"' -f $operationsDll),
        ('/reference:"{0}"' -f (Join-Path $frameworkDir 'System.Web.Extensions.dll')),
        ('"{0}"' -f (Join-Path $repo 'src\native\OperationGate.cs')))
    $libraryBuild = Start-Process -FilePath $compiler -ArgumentList ($libraryArgs -join ' ') `
        -RedirectStandardOutput $compileOut -RedirectStandardError $compileErr -WindowStyle Hidden -Wait -PassThru
    if ($libraryBuild.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $operationsDll)) {
        throw 'Operations library compilation failed.'
    }

    # Normal and protected delivery must start from the SAME fully featured UI.
    $deliveryVersion = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
    & (Join-Path $PSScriptRoot 'public-ui.ps1') -Path $uiPath -Version ([string]$deliveryVersion.version) -VersionCode ([int64]$deliveryVersion.versionCode)
    $ui = [IO.File]::ReadAllText($uiPath,[Text.Encoding]::UTF8)''')
section(route, '    # Phase 3.1 cryptographic integrity:', '    $entries = @(', "    & (Join-Path $PSScriptRoot 'write-integrity-manifest.ps1') -AppDirectory $appDir -VersionPath $versionPath -Profile 'update'\n\n")
public = 'release/build-public.ps1'
replace(public, "    & (Join-Path $PSScriptRoot 'finalize-package.ps1') -OutputDirectory $baseOut", "    & (Join-Path $PSScriptRoot 'finalize-package.ps1') -OutputDirectory $baseOut\n    & (Join-Path $PSScriptRoot 'add-native-setup-routing.ps1') -OutputDirectory $baseOut")
replace(public, "            (Join-Path $repo 'src\\native\\PublicSetupEntry.cs')\n", "            (Join-Path $repo 'src\\native\\PublicSetupEntry.cs'),\n            (Join-Path $repo 'src\\native\\OperationGate.cs')\n")
replace(public, "    & (Join-Path $PSScriptRoot 'public-ui.ps1') -Path $uiPath -Version $version -VersionCode $versionCode", "    # Already transformed and routed in the shared base package; never apply twice.\n    Copy-Item (Join-Path $packageApp 'TailscaleQuickRepair.Operations.dll') (Join-Path $packageProgram 'TailscaleQuickRepair.Operations.dll') -Force")
replace(public, "    $entries = @(\n", "    & (Join-Path $PSScriptRoot 'write-integrity-manifest.ps1') -AppDirectory $packageApp -VersionPath (Join-Path $packageRoot 'version.json') -Profile 'setup'\n\n    $entries = @(\n")

polish = 'release/polish-ui-v2.ps1'
replace(polish, "        $verifiedReleaseFiles = 0\n", "        $verifiedReleaseFiles = 0\n        $guardianLease = $null\n")
replace(polish, "        try {\n            $requiredFiles = @(", """        try {
            Initialize-OperationGate
            $guardianLease = [Tqr.OperationGate]::TryAcquire($StateDir, 'integrity')
            if (-not $guardianLease) {
                $GuardianStatusText.Text = 'Waiting for another operation'
                $GuardianDetailText.Text = 'Let the current Quick Repair operation finish, then check integrity again.'
                return
            }
            $requiredFiles = @(""")
replace(polish, "                $NativeHostPath,\n", "                $NativeHostPath,\n                $OperationsLibraryPath,\n")
replace(polish, "            try { $GuardianCheckButton.IsEnabled = $true } catch {}\n        }\n    })", "            if ($guardianLease) { try { $guardianLease.Dispose() } catch {} }\n            try { $GuardianCheckButton.IsEnabled = $true } catch {}\n        }\n    })")
replace(polish, "                        [int]$integrityManifest.schema -ne 1 -or\n", "                        [string]$integrityManifest.product -cne 'Tailscale Quick Repair' -or\n                        [string]$integrityManifest.version -cne $ProductVersion -or\n                        [int]$integrityManifest.schema -ne 1 -or\n")
replace(polish, "                    foreach ($entry in @($integrityManifest.files)) {", """                    $expectedNames = @('Tailscale-Repair-UI.ps1','TailscaleQuickRepairUpdater.exe','TailscaleQuickRepairSetup.exe','TailscaleQuickRepair.Operations.dll')
                    if ([string]$integrityManifest.profile -eq 'setup') {
                        $expectedNames += 'TailscaleQuickRepair.exe','Advanced-Diagnostics.ps1'
                    }
                    elseif ([string]$integrityManifest.profile -ne 'update') {
                        throw 'Release integrity profile is unsupported.'
                    }
                    $fileNames = @($integrityManifest.files | ForEach-Object { [string]$_.path })
                    if ($fileNames.Count -ne $expectedNames.Count -or
                        @($fileNames | Sort-Object -Unique).Count -ne $expectedNames.Count -or
                        @($fileNames | Where-Object { $_ -notin $expectedNames }).Count -ne 0) {
                        throw 'Release integrity file coverage is incomplete or duplicated.'
                    }
                    foreach ($entry in @($integrityManifest.files)) {""")
replace(polish, "                            $name -match '[\\\\/]' -or\n", "                            $name -notin $expectedNames -or\n                            $name -match '[\\\\/]' -or\n")
replace(polish, "                        if ((Get-Item -LiteralPath $candidate -ErrorAction Stop).Length -ne $expectedSize) {", """                        if (((Get-Item -LiteralPath $candidate -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                            throw 'Release files cannot use a reparse point.'
                        }
                        if ((Get-Item -LiteralPath $candidate -ErrorAction Stop).Length -ne $expectedSize) {""")
replace(polish, "                    elseif ($startupValue -ieq $legacyStartup) {", "                    elseif ($startupValue -ieq $legacyStartup -and $issues.Count -eq 0) {")
replace(polish, "                    [void]$safeFixes.Add('Known-good snapshot rebuilt.')", "                    [void]$issues.Add('Known-good baseline could not be read. The previous record was preserved.')")
replace(polish, "            if ($issues.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($integrityManifestSha256)) {", """            if ($snapshot -and (
                [int]$snapshot.schema -ne 1 -or [int64]$snapshot.versionCode -le 0 -or
                [int64]$snapshot.versionCode -gt $ProductVersionCode -or
                ([string]$snapshot.integrityManifestSha256).Length -ne 64 -or
                [string]$snapshot.integrityManifestSha256 -match '[^a-fA-F0-9]' -or
                [int]$snapshot.verifiedReleaseFiles -le 0)) {
                [void]$issues.Add('Known-good baseline metadata is invalid. The previous record was preserved.')
            }
            if ($issues.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($integrityManifestSha256)) {""")
replace(polish, '''                    $snapshotTemp = "$snapshotPath.$PID.tmp"
                    $snapshotJson = $snapshotValue | ConvertTo-Json -Depth 4
                    [IO.File]::WriteAllText($snapshotTemp,$snapshotJson,(New-Object System.Text.UTF8Encoding($false)))
                    if (Test-Path -LiteralPath $snapshotPath) { Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction Stop }
                    Move-Item -LiteralPath $snapshotTemp -Destination $snapshotPath -Force''', '''                    $snapshotTemp = $snapshotPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
                    $snapshotBackup = Join-Path $StateDir 'guardian-known-good.previous.json'
                    try {
                        foreach ($recordPath in @($snapshotPath,$snapshotBackup)) {
                            if ((Test-Path -LiteralPath $recordPath) -and
                                ((Get-Item -LiteralPath $recordPath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                                throw 'Known-good records cannot use a reparse point.'
                            }
                        }
                        $snapshotJson = $snapshotValue | ConvertTo-Json -Depth 4
                        $snapshotBytes = [Text.Encoding]::UTF8.GetBytes($snapshotJson)
                        $snapshotStream = [IO.File]::Open($snapshotTemp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                        try { $snapshotStream.Write($snapshotBytes,0,$snapshotBytes.Length); $snapshotStream.Flush($true) }
                        finally { $snapshotStream.Dispose() }
                        if (Test-Path -LiteralPath $snapshotPath) { [IO.File]::Replace($snapshotTemp,$snapshotPath,$snapshotBackup) }
                        else { [IO.File]::Move($snapshotTemp,$snapshotPath) }
                    }
                    finally {
                        if (Test-Path -LiteralPath $snapshotTemp) { Remove-Item -LiteralPath $snapshotTemp -Force -ErrorAction SilentlyContinue }
                    }''')
# Concise status, same check and evidence. No new dashboard boxes or animations.
replace(polish, "                [void]$healthyParts.Add('Configuration and Windows integration verified.')\n", "                [void]$healthyParts.Add('Windows integration checked.')\n")

workflow = '.github/workflows/release.yml'
replace(workflow, '    runs-on: windows-latest\n\n    outputs:', '    runs-on: windows-latest\n    timeout-minutes: 15\n\n    outputs:')
replace(workflow, '          $buildSetup = $requiresSetup -or $publicInstaller', '          $buildSetup = $true # Always validate both delivery paths, including normal-only releases.')
replace(workflow, '      - name: Require protected-migration assets\n', '''      - name: Native packaged runtime regression gates
        shell: powershell
        run: |
          .\\release\\test-packaged-runtime.ps1 -OutputDirectory .\\dist -EvidenceDirectory .\\test-evidence

      - name: Preserve runtime gate evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: runtime-evidence-${{ steps.meta.outputs.safe_version }}
          path: test-evidence/*.json
          if-no-files-found: warn

      - name: Require protected-migration assets
''')
privacy = 'release/privacy-scan.ps1'
replace(privacy, "    '.cs', '.vbs',", "    '.cs', '.vbs', '.py',")
# Wait for a complete child result, not merely the moment a result file appears.
test = 'release/test-packaged-runtime.ps1'
replace(test, '''        while(-not(Test-Path $Worker.Result) -and [DateTime]::UtcNow -lt $end){Start-Sleep -Milliseconds 20}
        if(-not(Test-Path $Worker.Result)){throw 'Native child did not report a result'}
        [IO.File]::ReadAllText($Worker.Result)''', '''        while([DateTime]::UtcNow -lt $end) {
            try {
                if(Test-Path $Worker.Result) {
                    $answer=[IO.File]::ReadAllText($Worker.Result)
                    if($answer -in @('acquired','busy')) { return $answer }
                }
            } catch {}
            Start-Sleep -Milliseconds 20
        }
        throw 'Native child did not report a complete result' ''')
version = json.loads(read('version.json'))
version.update(version='3.0.0-phase3.4.2', versionCode=30000442)
files['version.json'] = json.dumps(version, indent=2) + '\n'
publish = json.loads(read('release/publish.json'))
publish.update(publish=False, version=version['version'], versionCode=version['versionCode'],
               requiresSetup=True, publicInstaller=True,
               notes='Package parity and reliability hardening. Both delivery paths now include release-matched Guardian metadata and the same full UI. Baselines are replaced atomically with one local predecessor, and damaged records are preserved. A shared coordinator serializes ownership changes, never expires a live owner, preserves uncertain markers, and prevents rejected repair attempts from overwriting another result. Native Windows packaged-Guardian and cross-process regression gates are required before publishing. No Tailscale recovery algorithm or broad network reset changes.')
files['release/publish.json'] = json.dumps(publish, indent=2) + '\n'
for path, content in files.items():
    (root / path).write_text(content, encoding='utf-8', newline='\n')
    print('Prepared:', path)
print('Source preparation complete. Publishing remains disabled.')
