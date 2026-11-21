param([string]$Alias = 'hilva')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$store = Join-Path $root 'android/hilva-release.jks'
$properties = Join-Path $root 'android/key.properties'
if ((Test-Path -LiteralPath $store) -or (Test-Path -LiteralPath $properties)) { throw 'Existing signing material preserved. Back up and reuse it; do not regenerate.' }
$secret = Read-Host 'Choose a strong keystore password (back up securely)' -AsSecureString
$credential = [PSCredential]::new('hilva', $secret)
$env:HILVA_STORE_PASSWORD = $credential.GetNetworkCredential().Password
try {
  & keytool -genkeypair -v -keystore $store -storepass:env HILVA_STORE_PASSWORD -keypass:env HILVA_STORE_PASSWORD -alias $Alias -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=Hilva, OU=Personal, O=Hilva, L=Bogota, ST=Bogota, C=CO'
  if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
  $escaped = $env:HILVA_STORE_PASSWORD.Replace('\','\\').Replace(':','\:').Replace('=','\=')
  $content = @("storePassword=$escaped", "keyPassword=$escaped", "keyAlias=$Alias", 'storeFile=../hilva-release.jks') -join [Environment]::NewLine
  [IO.File]::WriteAllText($properties, $content, [Text.UTF8Encoding]::new($false))
  Write-Host 'Signing identity created. Back up android/hilva-release.jks and android/key.properties privately.'
} finally { Remove-Item Env:HILVA_STORE_PASSWORD }
