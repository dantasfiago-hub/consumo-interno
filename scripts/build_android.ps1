$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter não encontrado no PATH. Consulte LEIA_PRIMEIRO.md.'
}
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Falha ao obter dependências.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'A análise encontrou problemas.' }
if (-not (Test-Path 'android/key.properties')) {
    throw 'Extraia o kit de assinatura na raiz do projeto antes de compilar o APK release.'
}
flutter build apk --release --target-platform android-arm64
if ($LASTEXITCODE -ne 0) { throw 'Falha na compilação. Confira flutter doctor e o SDK Android.' }
New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item 'build/app/outputs/flutter-apk/app-release.apk' 'dist/consumo_interno_android_teste.apk' -Force
Write-Host 'APK release assinado criado em dist/consumo_interno_android_teste.apk'
