param([Parameter(Mandatory=$true)][string]$Apk, [ValidateSet('arm64','universal')][string]$Kind)
$ErrorActionPreference='Stop'
$sdk=$env:ANDROID_SDK_ROOT
if(!$sdk){$sdk=$env:ANDROID_HOME}
if(!$sdk){
 $line=Get-Content (Join-Path $PSScriptRoot '../android/local.properties') | Where-Object {$_ -like 'sdk.dir=*'} | Select-Object -First 1
 if($line){$sdk=$line.Substring(8).Replace('\\','\').Replace('\:',':')}
}
if(!$sdk){throw 'Set ANDROID_SDK_ROOT for APK verification.'}
$build=Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Sort-Object Name -Descending | Select-Object -First 1
if(!$build){throw 'Android build-tools are required.'}
$java=if($env:JAVA_HOME){Join-Path $env:JAVA_HOME 'bin/java.exe'}else{'java'}
$report=& $java -jar (Join-Path $build.FullName 'lib/apksigner.jar') verify --print-certs $Apk
if($LASTEXITCODE -ne 0){throw 'APK signature verification failed.'}
$expected='ba897c5fa7a0b3e55c828d0e6b17b1f9640dfda37b07accce1b29e53b99a17ef'
if(($report -join "`n") -notmatch "certificate SHA-256 digest: $expected"){throw 'APK was not signed with the designated production certificate.'}
$inputPath=(Resolve-Path -LiteralPath $Apk).Path
$tempCopy=$null
try {
  if ($inputPath -match '[^\x00-\x7F]') {
    # Older aapt versions cannot decode non-ASCII filenames. Pass a relative ASCII name.
    $tempCopy=Join-Path ([IO.Path]::GetTempPath()) ("verify-"+[guid]::NewGuid()+".apk")
    Copy-Item -LiteralPath $inputPath -Destination $tempCopy
    Push-Location -LiteralPath (Split-Path -Parent $tempCopy)
    try { $badging=& (Join-Path $build.FullName 'aapt.exe') dump badging (Split-Path -Leaf $tempCopy) }
    finally { Pop-Location }
  } else {
    $badging=& (Join-Path $build.FullName 'aapt.exe') dump badging $inputPath
  }
  if($LASTEXITCODE -ne 0){throw 'Unable to inspect Android package.'}
} finally {
  if ($tempCopy -and (Test-Path -LiteralPath $tempCopy)) { Remove-Item -LiteralPath $tempCopy }
}
$text=$badging -join "`n"
$versionLine=Get-Content (Join-Path $PSScriptRoot '../pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1
if($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)'){throw 'Invalid package version.'}
$expectedVersion=$Matches[1]; $expectedCode=$Matches[2]
if($text -cnotmatch "(?m)^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'"){throw 'Missing APK identity.'}
if($Matches[1] -cne 'local.eatwhat.campus' -or $Matches[2] -cne $expectedCode -or $Matches[3] -cne $expectedVersion){throw 'Unexpected package or version.'}
if($Kind){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk).Path)
  try {
    $expectedAbis=if($Kind -eq 'arm64'){@('arm64-v8a')}else{@('arm64-v8a','armeabi-v7a','x86_64')}
    foreach($library in 'libapp.so','libflutter.so'){
      $pattern='^lib/([^/]+)/'+[regex]::Escape($library)+'$'
      $actualAbis=@(foreach($entry in $archive.Entries){if($entry.FullName -cmatch $pattern){$Matches[1]}})
      if(($actualAbis | Sort-Object -Unique) -join ',' -cne ($expectedAbis -join ',')){throw "Unexpected ABI for $library in $Kind APK."}
    }
  } finally {$archive.Dispose()}
}
if($text -match 'application-debuggable'){throw 'Debuggable APK cannot be released.'}
Write-Host 'PASS: production certificate, signature, package, version and non-debuggable flag.'
$badging | Select-String "sdkVersion:|targetSdkVersion:|native-code:"
Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash)
