param([Parameter(Mandatory=$true)][string]$UiPath,[Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Native Windows PowerShell 5.1 required.' }
$root=Join-Path $env:TEMP ('TQR-RouteTest-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$cases=New-Object 'Collections.Generic.List[object]'
function Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED update route: $Name" }
    $cases.Add([pscustomobject]@{name=$Name;passed=$true});Write-Host "PASS update route: $Name"
}
$oldProbe=$env:TQR_ROUTING_PROBE
try {
    # Harmless native child substituted only as the fixture EXE path. Production
    # route code and the actual packaged WPF button are executed unchanged.
    $stub=Join-Path $root 'probe.exe'
    Add-Type -TypeDefinition @'
using System;
using System.IO;
public class TqrRouteProbe {
    public static void Main(string[] args) {
        File.WriteAllLines(Environment.GetEnvironmentVariable("TQR_ROUTING_PROBE"),args);
    }
}
'@ -OutputAssembly $stub -OutputType WindowsApplication
    $text=[IO.File]::ReadAllText($UiPath,[Text.Encoding]::UTF8)
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    $functions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-UpdateInstall'},$true))
    Check ($functions.Count -eq 1 -and $errors.Count -eq 0) 'Final package has one parsed update action'
    . ([scriptblock]::Create($functions[0].Extent.Text))
    function Get-Brush([string]$Name) { return [Windows.Media.Brushes]::Gray }
    $handlers=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -ceq '$UpdateNowButton' -and $n.Member.Value -eq 'Add_Click'},$true))
    Check ($handlers.Count -eq 1) 'Final package has one Update now event'
    $xamlMatch=[regex]::Match($text,'(?s)\[xml\]\$xaml\s*=\s*@"\r?\n(?<xaml>.*?)\r?\n"@')
    foreach($kind in @('protected','ordinary','invalid')) {
        [xml]$xaml=$xamlMatch.Groups['xaml'].Value
        $reader=New-Object Xml.XmlNodeReader $xaml;$window=[Windows.Markup.XamlReader]::Load($reader);$reader.Close()
        $UpdateNowButton=$window.FindName('UpdateNowButton');$CheckForUpdatesButton=$window.FindName('CheckForUpdatesButton')
        $UpdateStatusText=$window.FindName('UpdateStatusText');$UpdateDetailText=$window.FindName('UpdateDetailText')
        $SetupHostPath=$stub;$UpdaterHostPath=$stub;$ProductVersionCode=[int64]1
        $script:repairActive=$false;$script:updateDownloadActive=$false
        $flag=switch($kind){'protected'{$true};'ordinary'{$false};default{'not-a-boolean'}}
        $script:updateManifest=[pscustomobject]@{versionCode=2;version='fixture';requiresSetup=$flag}
        $probe=Join-Path $root ($kind+'.args');$env:TQR_ROUTING_PROBE=$probe
        $UpdateNowButton.IsEnabled=$true
        $UpdateNowButton.Add_Click($handlers[0].Arguments[0].ScriptBlock.GetScriptBlock())
        $UpdateNowButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if($kind -eq 'invalid') {
            Start-Sleep -Milliseconds 150
            Check (-not(Test-Path $probe) -and $UpdateStatusText.Text -eq 'Update metadata is invalid') 'Invalid protection flag starts no installer or ordinary updater'
        } else {
            $end=[DateTime]::UtcNow.AddSeconds(8)
            while(-not(Test-Path $probe) -and [DateTime]::UtcNow -lt $end){Start-Sleep -Milliseconds 30}
            Check (Test-Path $probe) "$kind click starts the native fixture child"
            $probeArgs=@(Get-Content $probe)
            if($kind -eq 'protected') { Check ($probeArgs.Count -eq 1 -and $probeArgs[0] -eq '--upgrade') 'Protected release invokes Setup --upgrade, not the ordinary updater' }
            else { Check ($probeArgs[0] -eq '--silent' -and $probeArgs -contains '--current-pid' -and $probeArgs -notcontains '--upgrade') 'Ordinary release invokes the normal native updater' }
        }
        $window.Close()
    }
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'update-routing-results.json'),(@{passed=$true;scope='Actual packaged WPF Update now event with harmless native executable fixture';cases=$cases.ToArray()}|ConvertTo-Json -Depth 8))
} catch {
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'update-routing-results.json'),(@{passed=$false;failure=$_.Exception.Message;cases=$cases.ToArray()}|ConvertTo-Json -Depth 8));throw
} finally {$env:TQR_ROUTING_PROBE=$oldProbe}
