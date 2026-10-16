$ErrorActionPreference='Stop'
$sdkPath=Join-Path $env:LOCALAPPDATA 'Android\sdk'
if ($env:ANDROID_HOME) { $sdkPath=$env:ANDROID_HOME }
$properties=Join-Path $PSScriptRoot 'android\local.properties'
if (Test-Path -LiteralPath $properties) {
  $sdkLine=Get-Content -LiteralPath $properties | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
  if ($sdkLine) { $sdkPath=$sdkLine.Substring(8).Replace('\\','\').Replace('\:',':') }
}
Write-Host ('Android SDK: '+$sdkPath)
$requirements=@(
  @('platforms\android-36\android.jar','Android SDK Platform 36'),
  @('build-tools\36.0.0\aapt2.exe','Android SDK Build-Tools 36.0.0'),
  @('ndk\28.2.13676358\source.properties','NDK (Side by side) 28.2.13676358'),
  @('cmdline-tools\latest\bin\sdkmanager.bat','Android SDK Command-line Tools (latest)'),
  @('platform-tools\adb.exe','Android SDK Platform-Tools')
)
$missing=0
foreach ($item in $requirements) {
  if (Test-Path -LiteralPath (Join-Path $sdkPath $item[0])) { Write-Host ('[OK] '+$item[1]) }
  else { Write-Host ('[MISSING] '+$item[1]); $missing++ }
}
if ($missing) {
  Write-Host 'Install missing components using Android Studio > SDK Manager.'
  Write-Host 'Use Show Package Details to select the exact NDK version.'
  Write-Host 'Then run build-android.cmd. The first Gradle build requires network access.'
} else { Write-Host 'SDK files found. Build and device testing are still required.' }
