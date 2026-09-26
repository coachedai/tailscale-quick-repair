param([Parameter(Mandatory=$true)][string]$BackendPath,[Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($BackendPath,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) {throw 'Packaged backend does not parse.'}
$wanted=@('Publish-State','Get-TailscaleNetworkAdapters','Repair-TailscaleAdapter')
$functions=@{}
foreach($name in $wanted){
    $nodes=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
    if($nodes.Count -ne 1){throw ('Packaged backend function is missing or duplicated: '+$name)}
    $functions[$name]=$nodes[0]
    . ([scriptblock]::Create($nodes[0].Extent.Text))
}
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
    # Harmless adapter-scope fixture. Every Windows/network command below is
    # shadowed by a local function; no real adapter or service is changed.
    $script:adapterFixture=@(
        [pscustomobject]@{Name='Tailscale';InterfaceDescription='Third Party VPN Adapter'}
        [pscustomobject]@{Name='Corporate Tailscale Alias';InterfaceDescription='Corporate VPN Tunnel'}
        [pscustomobject]@{Name='Renamed by user';InterfaceDescription='Tailscale Tunnel'}
        [pscustomobject]@{Name='Other VPN';InterfaceDescription='TAP Virtual Adapter'}
    )
    $script:disabledAdapters=New-Object 'Collections.Generic.List[string]'
    $script:enabledAdapters=New-Object 'Collections.Generic.List[string]'
    function Get-NetAdapter {[CmdletBinding()]param([switch]$IncludeHidden) @($script:adapterFixture)}
    function Disable-NetAdapter {[CmdletBinding()]param([Parameter(Mandatory=$true)][object]$InputObject,[switch]$Confirm) $script:disabledAdapters.Add([string]$InputObject.InterfaceDescription)}
    function Enable-NetAdapter {[CmdletBinding()]param([Parameter(Mandatory=$true)][object]$InputObject,[switch]$Confirm) $script:enabledAdapters.Add([string]$InputObject.InterfaceDescription)}
    function Restart-TailscaleService {param([string]$Cli) return $true}
    function Publish-State {}
    function Add-Event {param([string]$Text)}
    function Start-Sleep {param([int]$Seconds)}

    $selected=@(Get-TailscaleNetworkAdapters)
    if($selected.Count -ne 1 -or [string]$selected[0].InterfaceDescription -cne 'Tailscale Tunnel'){
        throw 'Adapter selector did not fail closed to the exact Tailscale tunnel description.'
    }
    $script:RepairPerformed=$false
    if(-not (Repair-TailscaleAdapter 'fixture')){throw 'Adapter recovery fixture did not reach its Tailscale-only service fallback.'}
    if($script:disabledAdapters.Count -ne 1 -or $script:enabledAdapters.Count -ne 1 -or
       $script:disabledAdapters[0] -cne 'Tailscale Tunnel' -or $script:enabledAdapters[0] -cne 'Tailscale Tunnel'){
        throw 'Adapter recovery attempted to touch an adapter outside the exact Tailscale tunnel.'
    }

    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'backend-report-results.json'),
        (@{passed=$true;cases=4;scope='Packaged state publisher plus mocked exact Tailscale-adapter selection; no real networking or service changes'}|ConvertTo-Json -Compress))
    Write-Host 'PASS: Packaged backend reports repair state and limits adapter recovery to the exact Tailscale tunnel.'
} catch {
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'backend-report-results.json'),(@{passed=$false;failure=$_.Exception.Message}|ConvertTo-Json));throw
}
