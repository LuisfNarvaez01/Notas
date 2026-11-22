param(
  [Parameter(Mandatory)][string]$PreviousArchive,
  [Parameter(Mandatory)][string]$NewArchive
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$previous = (Resolve-Path -LiteralPath $PreviousArchive).Path
$next = (Resolve-Path -LiteralPath $NewArchive).Path
$root = Join-Path $repo ('build\updater-smoke-' + [guid]::NewGuid())
$target = Join-Path $root 'portable with spaces'
$temp = Join-Path $root 'helper'
$state = Join-Path $root 'status.json'
New-Item -ItemType Directory -Path $root, $temp | Out-Null
Expand-Archive -LiteralPath $previous -DestinationPath $target
$flutter = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
$dart = Join-Path $flutter 'bin\cache\dart-sdk\bin\dart.exe'
function Invoke-Probe([string]$ArchivePath) {
  $arguments = @(
    ('--packages="' + (Join-Path $repo '.dart_tool\package_config.json') + '"'),
    ('"' + (Join-Path $repo 'tool\windows_update_probe.dart') + '"'),
    ('"' + (Join-Path $repo 'scripts\update-windows.ps1') + '"'),
    ('"' + $ArchivePath + '"'), ('"' + $target + '"'),
    ('"' + $temp + '"'), ('"' + $state + '"')
  )
  $process = Start-Process -FilePath $dart -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'parent.out') -RedirectStandardError (Join-Path $root 'parent.err')
  if (-not $process.WaitForExit(60000)) { throw 'Test parent did not finish in 60 seconds' }
  return $process.ExitCode
}
$exitCode = Invoke-Probe $next
if ($exitCode -ne 0) { throw (Get-Content -LiteralPath (Join-Path $root 'parent.err') -Raw) }
$deadline = [DateTime]::UtcNow.AddSeconds(30)
do {
  Start-Sleep -Milliseconds 250
  $result = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
} while ($result.status -eq 'ready' -and [DateTime]::UtcNow -lt $deadline)
if ($result.status -ne 'completed') { throw ('Update failed: ' + $result.message) }
$expected = Join-Path $root 'expected'
Expand-Archive -LiteralPath $next -DestinationPath $expected
if ((Get-FileHash -LiteralPath (Join-Path $target 'hilva.exe')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $expected 'hilva.exe')).Hash) { throw 'Executable mismatch' }
$exe = Join-Path $target 'hilva.exe'
$launched = @(Get-Process hilva -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
if ($launched.Count -eq 0) { throw 'Updated app did not start' }
# Stop only the processes launched from this isolated test installation.
$launched | Stop-Process
$bad = Join-Path $root 'invalid.zip'
Set-Content -LiteralPath $bad -Value 'invalid zip' -Encoding ascii
$before = (Get-FileHash -LiteralPath $exe).Hash
$exitCode = Invoke-Probe $bad
if ($exitCode -eq 0) { throw 'Invalid archive was accepted' }
$result = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
if ($result.status -ne 'failed') { throw 'Preflight failure not reported' }
if ((Get-FileHash -LiteralPath $exe).Hash -ne $before) { throw 'Failed preflight modified installation' }
Write-Output 'PASS: parent held target working directory; helper prepared, replaced and restarted the app.'
Write-Output 'PASS: corrupt archive rejected before closing parent or modifying installation.'
Write-Output ('Evidence: ' + $root)
