param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$SkipRepositoryIdentity
)

$ErrorActionPreference = 'Stop'
$ExpectedRepository = 'coachedai/tailscale-quick-repair'
$rootPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)

function Add-Finding {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path,
        [string]$Reason
    )

    $List.Add("$Path :: $Reason")
}

$findings = New-Object 'System.Collections.Generic.List[string]'

if (-not $SkipRepositoryIdentity) {
    if (
        -not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY) -and
        $env:GITHUB_REPOSITORY -ne $ExpectedRepository
    ) {
        throw "Repository isolation check failed. Expected $ExpectedRepository, got $($env:GITHUB_REPOSITORY)."
    }

    try {
        $origin = (& git -C $rootPath remote get-url origin 2>$null | Select-Object -First 1).Trim()

        if (
            $origin -and
            $origin -notmatch '(?i)(github\.com[:/])coachedai/tailscale-quick-repair(?:\.git)?$'
        ) {
            throw "Repository isolation check failed. Unexpected origin: $origin"
        }
    }
    catch {
        if ($env:GITHUB_ACTIONS -eq 'true') {
            throw
        }
    }
}

$tracked = @()

if (
    -not $SkipRepositoryIdentity -and
    (Test-Path -LiteralPath (Join-Path $rootPath '.git'))
) {
    $tracked = @(& git -C $rootPath ls-files)
}
else {
    $tracked = @(
        Get-ChildItem -LiteralPath $rootPath -File -Recurse -Force |
            Where-Object {
                $_.FullName -notmatch '[\\/]\.git[\\/]' -and
                $_.FullName -notmatch '[\\/]dist[\\/]'
            } |
            ForEach-Object {
                $_.FullName.Substring($rootPath.Length).TrimStart('\','/') -replace '\\','/'
            }
    )
}

# Construct the other-project token dynamically so the scanner does not match itself.
$otherProjectToken = ('coach' + 'intake')

$forbiddenFileNames = @(
    '.env',
    '.env.local',
    'config.json',
    'secrets.json',
    'credentials.json',
    'id_rsa',
    'id_ed25519'
)

$textExtensions = @(
    '.ps1', '.psm1', '.psd1',
    '.cs', '.vbs',
    '.json', '.yml', '.yaml',
    '.md', '.txt', '.gitignore',
    '.xml', '.config'
)

$secretPatterns = @(
    @{ Name = 'GitHub token'; Pattern = '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}\b' },
    @{ Name = 'GitHub fine-grained token'; Pattern = '(?i)\bgithub_pat_[A-Za-z0-9_]{20,}\b' },
    @{ Name = 'Tailscale auth key'; Pattern = '(?i)\btskey-[A-Za-z0-9-]{10,}\b' },
    @{ Name = 'AWS access key'; Pattern = '\bAKIA[0-9A-Z]{16}\b' },
    @{ Name = 'Private key'; Pattern = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----' },
    @{ Name = 'OpenAI-style secret'; Pattern = '(?i)\bsk-[A-Za-z0-9_-]{20,}\b' }
)

$windowsUserPathPattern = '(?i)\b[A-Z]:\\Users\\([^\\\r\n]+)'
$deviceNamePattern = '(?i)\bvmi\d{5,}\b'
$emailPattern = '(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b'
$ipv4Pattern = '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'

foreach ($relative in $tracked) {
    if ([string]::IsNullOrWhiteSpace($relative)) { continue }

    $relativeNormalized = $relative -replace '\\','/'
    $leaf = [IO.Path]::GetFileName($relativeNormalized)

    if ($relativeNormalized -match '(?i)(^|/)' + [regex]::Escape($otherProjectToken) + '(/|$)') {
        Add-Finding $findings $relativeNormalized 'Cross-project path detected. This repository must stay isolated.'
    }

    if (
        $forbiddenFileNames -contains $leaf -or
        $leaf -match '(?i)\.(pem|pfx|p12|key)$'
    ) {
        Add-Finding $findings $relativeNormalized 'Sensitive/local configuration file must not be tracked.'
    }

    $extension = [IO.Path]::GetExtension($leaf).ToLowerInvariant()

    if (
        -not ($textExtensions -contains $extension) -and
        $leaf -ne '.gitignore'
    ) {
        continue
    }

    $fullPath = [IO.Path]::GetFullPath((Join-Path $rootPath $relativeNormalized))

    if (-not $fullPath.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        Add-Finding $findings $relativeNormalized 'Path escapes repository root.'
        continue
    }

    if (-not (Test-Path -LiteralPath $fullPath)) { continue }

    $file = Get-Item -LiteralPath $fullPath

    if ($file.Length -gt 5MB) {
        Add-Finding $findings $relativeNormalized 'Unexpected text file larger than 5 MB.'
        continue
    }

    $content = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop

    if ($content.IndexOf($otherProjectToken, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Add-Finding $findings $relativeNormalized 'Cross-project content detected.'
    }

    foreach ($pattern in $secretPatterns) {
        if ($content -match $pattern.Pattern) {
            Add-Finding $findings $relativeNormalized $pattern.Name
        }
    }

    foreach ($match in [regex]::Matches($content, $windowsUserPathPattern)) {
        $userSegment = $match.Groups[1].Value

        if ($userSegment -notin @('Public', '<user>', 'USERNAME', '$env:USERNAME')) {
            Add-Finding $findings $relativeNormalized 'Personal Windows user-profile path detected.'
        }
    }

    if ($content -match $deviceNamePattern) {
        Add-Finding $findings $relativeNormalized 'Machine-specific VPS/device name detected.'
    }

    foreach ($match in [regex]::Matches($content, $emailPattern)) {
        $email = $match.Value

        if ($email -notmatch '(?i)@users\.noreply\.github\.com$') {
            Add-Finding $findings $relativeNormalized "Email address detected: $email"
        }
    }

    foreach ($match in [regex]::Matches($content, $ipv4Pattern)) {
        $value = $match.Value

        # Protocol/version literals only. Real network addresses are blocked.
        if ($value -in @('0.0.0.0', '127.0.0.1', '2.0.0.0', '3.0.0.0')) {
            continue
        }

        $octets = @($value.Split('.') | ForEach-Object { [int]$_ })

        if ($octets.Count -ne 4 -or ($octets | Where-Object { $_ -gt 255 }).Count -gt 0) {
            continue
        }

        Add-Finding $findings $relativeNormalized "Literal IPv4 address detected: $value"
    }
}

if ($findings.Count -gt 0) {
    Write-Host ''
    Write-Host 'PRIVACY / PROJECT ISOLATION CHECK FAILED' -ForegroundColor Red

    foreach ($finding in $findings) {
        Write-Host " - $finding" -ForegroundColor Red
    }

    Write-Host ''
    throw "Blocked $($findings.Count) potentially sensitive or cross-project item(s)."
}

Write-Host "Privacy and project-isolation scan passed ($($tracked.Count) files checked)." -ForegroundColor Green
