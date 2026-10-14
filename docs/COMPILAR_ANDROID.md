# Compilar Android — 1.6.1+9

SDK 34/35 também são instalados porque alguns plugins compilam contra essas plataformas.

Configuração Android: Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.21, Java 17, API 36, Build Tools 35.0.0 e NDK 28.2.13676358. API/NDK são fixados para evitar mudanças silenciosas quando o Flutter for atualizado. Flutter de referência: 3.47.5. Não é necessária migração para AGP 9 nem ignorar a validação de dependências.

## SDK sem Android Studio (Ubuntu x86_64)

Instale `openjdk-17-jdk` e `unzip` pelo apt. Baixe as Android Command-line Tools Linux em https://developer.android.com/studio#command-tools. Extraia bin/lib/NOTICE/source.properties para `$HOME/Android/Sdk/cmdline-tools/latest/`.

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "platforms;android-35" "platforms;android-36" "build-tools;35.0.0" "ndk;28.2.13676358" "cmake;3.22.1"
flutter config --jdk-dir "$JAVA_HOME"
flutter config --android-sdk "$ANDROID_HOME"
flutter doctor --android-licenses
flutter doctor -v
java -version
javac -version
```

Adapte caminhos ao seu computador. Leia/aceite as licenças. Internet é necessária para instalar as dependências e compilar pela primeira vez.

## Compilação

Na raiz onde está pubspec.yaml, execute:

```bash
flutter pub get
flutter analyze --suggestions
flutter analyze
flutter test
flutter build apk --debug
```

APK de teste: `build/app/outputs/flutter-apk/app-debug.apk`.

Para produção, extraia o kit de assinatura privado na raiz, mantendo `android/key.properties` e `android/signing/release-keystore.p12`. Se configurar manualmente, use `android/key.properties.example` como modelo; preencha as senhas e alias reais. Nunca use os placeholders para assinar. O caminho storeFile é relativo à pasta android ou absoluto.

```bash
flutter build apk --release
```

APK release: `build/app/outputs/flutter-apk/app-release.apk`. A versão será 1.6.1, código 9. Use a mesma chave do APK anterior para atualização; preserve dados e pendências antes de qualquer desinstalação. A pasta supabase pode continuar dentro do projeto: os SQL são aplicados separadamente no servidor.

O Flutter 3.47.5 aceita esta configuração, mas emite avisos de suporte futuro para Gradle/AGP/Kotlin. Avisos não são erros de compilação. Não foi usado --android-skip-build-dependency-validation. A migração para AGP 9 deve ser testada com todos os plugins antes de uma atualização futura.

## GitHub

A chave privada, key.properties, local.properties, builds e configurações reais não são publicados. O exemplo sem segredo é versionado. O workflow build.yml testa Flutter/SQL e compila Windows e APK debug. O job release só executa fora de pull requests quando a variável CONSUMO_ANDROID_RELEASE está habilitada e os secrets de assinatura estão configurados. A assinatura pode permanecer apenas no computador local. Não fornece URL/chave/UUID da sua loja ao workflow. Após clonar, siga o guia Supabase e ative o aparelho normalmente.

## Fontes das versões

- https://developer.android.com/build/releases/agp-8-11-0-release-notes
- https://kotlinlang.org/docs/gradle-configure-project.html
- https://docs.gradle.org/8.14.3/release-notes.html
