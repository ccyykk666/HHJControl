[CmdletBinding()]
param(
    [string]$Repository = "ccyykk666/HHJControl",
    [Parameter(Mandatory = $true)][string]$CertificatePath,
    [Parameter(Mandatory = $true)][string]$ProvisioningProfilePath
)

$ErrorActionPreference = "Stop"

function Set-GitHubSecretWithoutNewline {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$RepositoryName
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command gh).Source
    $startInfo.Arguments = "secret set $Name --repo $RepositoryName"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $process.StandardInput.Write($Value)
    $process.StandardInput.Close()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Failed to set GitHub secret $Name. $standardError"
    }
    if ($standardOutput) { Write-Host $standardOutput.TrimEnd() }
}

foreach ($path in @($CertificatePath, $ProvisioningProfilePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "File not found: $path"
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required."
}

$securePassword = Read-Host "Enter the .p12 password (input is hidden)" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $certificateBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $CertificatePath)))
    $profileBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ProvisioningProfilePath)))

    Set-GitHubSecretWithoutNewline -Name CERT_P12_BASE64 -Value $certificateBase64 -RepositoryName $Repository
    Set-GitHubSecretWithoutNewline -Name CERT_PASSWORD -Value $plainPassword -RepositoryName $Repository
    Set-GitHubSecretWithoutNewline -Name PROVISIONING_PROFILE_BASE64 -Value $profileBase64 -RepositoryName $Repository
    Write-Host "Signing secrets were configured for $Repository. No signing material was written to the repository."
}
finally {
    if ($null -ne $passwordPointer) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
    $plainPassword = $null
    $certificateBase64 = $null
    $profileBase64 = $null
}
