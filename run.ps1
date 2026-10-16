param(
  [ValidateSet('check','doctor','windows','android','run-windows')][string]$Target='check',
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
if (!$Flutter -or !(Test-Path -LiteralPath $Flutter)) { throw '找不到 Flutter SDK。设置 FLUTTER_ROOT，或使用 -Flutter 指定 flutter.bat。' }
# Reuse the existing mirror cache without changing machine-wide settings.
if ($env:PUB_CACHE -and !$env:PUB_HOSTED_URL -and (Test-Path -LiteralPath (Join-Path $env:PUB_CACHE 'hosted\pub.flutter-io.cn'))) {
  $env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
}
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
  if ($Target -eq 'windows') { Invoke-Flutter @('build','windows','--no-pub','--release') }
  if ($Target -eq 'android') {
    Invoke-Flutter @('build','apk','--no-pub','--debug')
    $apk=Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (!(Test-Path -LiteralPath $apk)) { throw 'Build completed without the expected APK.' }
    $delivery=Join-Path (Split-Path -Parent $PSScriptRoot) 'eat-what-android-debug.apk'
    Copy-Item -LiteralPath $apk -Destination $delivery -Force
    Write-Host ('APK: '+$delivery)
    Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $delivery -Algorithm SHA256).Hash)
  }
  if ($Target -eq 'run-windows') { Invoke-Flutter @('run','--no-pub','-d','windows') }
} catch { Write-Host ('FAILED: '+$_.Exception.Message); exit 1 }
finally { Stop-Transcript }
