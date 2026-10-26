param(
  [ValidateSet('check','doctor','android','android-release')][string]$Target='check',
  [string]$Flutter='',
  [switch]$Online
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
Set-Location -LiteralPath $PSScriptRoot
if (!$Flutter -and $env:FLUTTER_ROOT) { $Flutter=Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat' }
if (!$Flutter) {
  $found=Get-Command flutter -ErrorAction SilentlyContinue
  if ($found) { $Flutter=$found.Source }
}
if (!$Flutter -or !(Test-Path -LiteralPath $Flutter)) { throw '请设置 FLUTTER_ROOT，或使用 -Flutter 指定本机 flutter.bat。' }
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'logs') -Force | Out-Null
Start-Transcript -LiteralPath (Join-Path $PSScriptRoot "logs\$Target.txt") -Force
function Invoke-Flutter([string[]]$Arguments) {
  $start=[Diagnostics.ProcessStartInfo]::new()
  $start.FileName=$env:ComSpec
  $quoted='"'+$Flutter+'"'
  foreach($argument in $Arguments) { $quoted+=' "'+$argument+'"' }
  $start.Arguments='/d /s /c "'+$quoted+'"'
  $start.WorkingDirectory=$PSScriptRoot
  $start.UseShellExecute=$false
  $start.CreateNoWindow=$true
  $start.RedirectStandardOutput=$true
  $start.RedirectStandardError=$true
  $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
  $start.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
  Write-Host ('flutter '+($Arguments -join ' '))
  $process=[Diagnostics.Process]::Start($start)
  $stdout=$process.StandardOutput.ReadToEndAsync()
  $stderr=$process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  Write-Host $stdout.Result
  if ($stderr.Result) { Write-Host $stderr.Result }
  $code=$process.ExitCode
  $process.Dispose()
  if ($code -ne 0) { throw "Flutter 返回错误码 $code；请查看日志。" }
}
try {
  if ($Target -eq 'doctor') { Invoke-Flutter @('doctor','-v'); exit 0 }
  if ($Online) { Invoke-Flutter @('pub','get') }
  else { Invoke-Flutter @('pub','get','--offline') }
  Invoke-Flutter @('analyze','--no-pub','lib','test')
  Invoke-Flutter @('test','--no-pub')
  if ($Target -eq 'android') {
    Invoke-Flutter @('build','apk','--no-pub','--debug')
    $apk=Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (!(Test-Path -LiteralPath $apk)) { throw 'Build completed without the expected APK.' }
    $delivery=Join-Path (Split-Path -Parent $PSScriptRoot) 'eat-what-android-debug.apk'
    Copy-Item -LiteralPath $apk -Destination $delivery -Force
    Write-Host ('APK: '+$delivery)
    Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $delivery -Algorithm SHA256).Hash)
  }
  if ($Target -eq 'android-release') {
    $deliveryRoot=Split-Path -Parent $PSScriptRoot
    $versionLine=Get-Content (Join-Path $PSScriptRoot 'pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1
    if($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)'){throw 'Invalid package version.'}
    $releaseVersion=$Matches[1]; $releaseBuild=$Matches[2]
    Invoke-Flutter @('build','apk','--no-pub','--release','--target-platform','android-arm64')
    $apk=Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-release.apk'
    $arm64=Join-Path $deliveryRoot "EatenYet-v$releaseVersion-build$releaseBuild-android-arm64.apk"
    Copy-Item -LiteralPath $apk -Destination $arm64 -Force
    Invoke-Flutter @('build','apk','--no-pub','--release')
    $universal=Join-Path $deliveryRoot "EatenYet-v$releaseVersion-build$releaseBuild-android-universal.apk"
    Copy-Item -LiteralPath $apk -Destination $universal -Force
    foreach($file in @($arm64,$universal)) {
      & (Join-Path $PSScriptRoot 'scripts/verify-apk.ps1') -Apk $file
      Write-Host ('APK: '+$file)
      Write-Host ('Bytes: '+(Get-Item -LiteralPath $file).Length)
      Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash)
    }
  }
} catch { Write-Host ('FAILED: '+$_.Exception.Message); exit 1 }
finally { Stop-Transcript }
