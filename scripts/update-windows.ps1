param([Parameter(Mandatory)][string]$Archive, [Parameter(Mandatory)][string]$Destination, [Parameter(Mandatory)][int]$WaitPid, [Parameter(Mandatory)][string]$ExpectedHash, [string]$StateFile)
$ErrorActionPreference = 'Stop'
function Write-UpdateState([string]$Status, [string]$Message) {
  if ($StateFile) {
    @{ status = $Status; message = $Message; time = [DateTime]::UtcNow.ToString('o') } |
      ConvertTo-Json -Compress | Set-Content -LiteralPath $StateFile -Encoding UTF8
  }
}
# A child must not retain the application's directory while replacing it.
Set-Location -LiteralPath ([IO.Path]::GetTempPath())
[Environment]::CurrentDirectory = [IO.Path]::GetTempPath()
try {
Write-UpdateState 'preparing' 'Verificando y preparando el paquete.'
$target = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$parent = Split-Path -Parent $target
if (-not $parent -or -not (Test-Path -LiteralPath (Join-Path $target 'hilva.exe'))) { throw 'Invalid application directory' }
if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Application directory cannot be a link' }
if ($ExpectedHash -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Package integrity check failed' }
$stage = Join-Path $parent ('hilva-staging-' + [guid]::NewGuid())
$backup = Join-Path $parent ('hilva-backup-' + [guid]::NewGuid())
$failed = Join-Path $parent ('hilva-failed-' + [guid]::NewGuid())
foreach ($path in @($stage, $backup, $failed)) {
  if ((Split-Path -Parent ([IO.Path]::GetFullPath($path))) -ne $parent) { throw 'Unsafe update paths' }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($Archive)
try {
  $expandedSize = 0L
  foreach ($entry in $zip.Entries) {
    if ($entry.FullName.Contains(':') -or [IO.Path]::IsPathRooted($entry.FullName)) { throw 'Unsafe archive path' }
    $entryPath = [IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
    if (-not $entryPath.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe archive path' }
    $expandedSize += $entry.Length
    if ($expandedSize -gt 2GB) { throw 'Expanded package too large' }
  }
} finally { $zip.Dispose() }
Expand-Archive -LiteralPath $Archive -DestinationPath $stage
if (-not (Test-Path -LiteralPath (Join-Path $stage 'hilva.exe'))) { throw 'Missing executable' }
if (-not (Test-Path -LiteralPath (Join-Path $stage 'data/flutter_assets'))) { throw 'Incomplete Flutter package' }
Write-UpdateState 'ready' 'Paquete preparado; esperando el cierre de Hilva.'
Wait-Process -Id $WaitPid -Timeout 120 -ErrorAction SilentlyContinue
if (Get-Process -Id $WaitPid -ErrorAction SilentlyContinue) { throw 'Application did not close' }
# Resolved sibling paths only. Preserve both the previous and failed packages.
Move-Item -LiteralPath $target -Destination $backup
try {
  Move-Item -LiteralPath $stage -Destination $target
  Start-Process -FilePath (Join-Path $target 'hilva.exe') -WorkingDirectory $target -WindowStyle Hidden -ErrorAction Stop
  Write-UpdateState 'completed' 'Actualizacion instalada.'
} catch {
  if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $failed }
  Move-Item -LiteralPath $backup -Destination $target
  throw
}

} catch {
  Write-UpdateState 'failed' $_.Exception.Message
  # If Hilva has already exited, reopen the preserved installation to show status.
  if (-not (Get-Process -Id $WaitPid -ErrorAction SilentlyContinue) -and
      (Test-Path -LiteralPath (Join-Path $target 'hilva.exe'))) {
    Start-Process -FilePath (Join-Path $target 'hilva.exe') -WorkingDirectory $target -WindowStyle Hidden -ErrorAction SilentlyContinue
  }
  exit 1
}
