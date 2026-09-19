param([Parameter(Mandatory=$true)][string]$BackendPath,[Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($BackendPath,[ref]$tokens,[ref]$errors)
$functions=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Publish-State'},$true))
if ($errors.Count -gt 0 -or $functions.Count -ne 1) {throw 'Packaged backend reporting function is invalid.'}
. ([scriptblock]::Create($functions[0].Extent.Text))
$root=Join-Path $env:TEMP ('TQR-ReportTest-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$StateFile=Join-Path $root 'state.json'
$script:Diag=@{client='Running';service='Running';backend='Running';route='Direct';latency='12 ms'}
$script:EventItems=@()
try {
    foreach ($performed in @($false,$true)) {
        $script:RepairPerformed=$performed
        Publish-State 'Fixture status' 'Fixture detail' 100 'success' 'Complete' $true
        $result=Get-Content $StateFile -Raw|ConvertFrom-Json
        if ($result.repairPerformed -isnot [bool] -or $result.repairPerformed -ne $performed) {
            throw 'Published state lost the actual repair-performed flag.'
        }
    }
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'backend-report-results.json'),'{"passed":true,"cases":2,"scope":"Packaged state publisher only; no networking or service changes"}')
    Write-Host 'PASS: Packaged backend reports both no-repair and actual-repair state correctly.'
} catch {
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'backend-report-results.json'),(@{passed=$false;failure=$_.Exception.Message}|ConvertTo-Json));throw
}
