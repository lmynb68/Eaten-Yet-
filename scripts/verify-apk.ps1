param([Parameter(Mandatory=$true)][string]$Apk)
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
$badging=& (Join-Path $build.FullName 'aapt.exe') dump badging $Apk
if($LASTEXITCODE -ne 0){throw 'Unable to inspect Android package.'}
$text=$badging -join "`n"
$versionLine=Get-Content (Join-Path $PSScriptRoot '../pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1
if($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)'){throw 'Invalid package version.'}
$expectedVersion=[regex]::Escape($Matches[1]); $expectedCode=$Matches[2]
if($text -notmatch "name='local.eatwhat.campus' versionCode='$expectedCode' versionName='$expectedVersion'"){throw 'Unexpected package or version.'}
if($text -match 'application-debuggable'){throw 'Debuggable APK cannot be released.'}
Write-Host 'PASS: production certificate, signature, package, version and non-debuggable flag.'
$badging | Select-String "sdkVersion:|targetSdkVersion:|native-code:"
Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash)
