[CmdletBinding()]
param(
    [string]$Repository = "ccyykk666/HHJControl",
    [Parameter(Mandatory = $true)][string]$CertificatePath,
    [Parameter(Mandatory = $true)][string]$ProvisioningProfilePath
)

$ErrorActionPreference = "Stop"

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

    $certificateBase64 | gh secret set CERT_P12_BASE64 --repo $Repository
    $plainPassword | gh secret set CERT_PASSWORD --repo $Repository
    $profileBase64 | gh secret set PROVISIONING_PROFILE_BASE64 --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Failed to write one or more GitHub secrets." }
    Write-Host "Signing secrets were configured for $Repository. No signing material was written to the repository."
}
finally {
    if ($null -ne $passwordPointer) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
    $plainPassword = $null
    $certificateBase64 = $null
    $profileBase64 = $null
}

