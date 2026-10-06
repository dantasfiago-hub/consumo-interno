$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter não encontrado no PATH. Consulte LEIA_PRIMEIRO.md.'
}
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Falha ao obter dependências.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'A análise encontrou problemas.' }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Falha na compilação. Confira flutter doctor e Visual Studio C++.' }
New-Item -ItemType Directory -Force dist | Out-Null
Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath 'dist/consumo_interno_windows.zip' -Force
Write-Host 'Pacote Windows criado em dist/consumo_interno_windows.zip'
if (Get-Command ISCC.exe -ErrorAction SilentlyContinue) {
    ISCC.exe installer/consumo_interno.iss
    if ($LASTEXITCODE -ne 0) { throw 'Falha no instalador Inno Setup.' }
}
