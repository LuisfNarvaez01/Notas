param([ValidateSet('android','windows')][string]$Platform = 'windows')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependencies failed' }
  flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Analysis failed' }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
  New-Item -ItemType Directory -Force build/distribution | Out-Null
  if ($Platform -eq 'android') {
    if (-not (Test-Path android/key.properties)) { throw 'Run scripts/create-signing-key.ps1 first.' }
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    Copy-Item build/app/outputs/flutter-apk/app-release.apk build/distribution/hilva-android.apk
  } else {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    Copy-Item scripts/update-windows.ps1 build/windows/x64/runner/Release/update-windows.ps1
    Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath build/distribution/hilva-windows.zip -Force
  }
  Get-ChildItem build/distribution -File | Where-Object { $_.Extension -in '.apk','.zip' } | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $_.Name } | Set-Content build/distribution/SHA256SUMS -Encoding ascii
} finally { Pop-Location }
