#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Asistencia Uniguajira · Script de desarrollo y ejecución
# Sistema de Asistencia Offline-First con BLE y SQLite
#
# Uso:
#   ./run.sh                  (Auto-detecta Android si está conectado, o ejecuta en Linux)
#   ./run.sh android          (Ejecuta en dispositivo Android conectado)
#   ./run.sh linux            (Ejecuta en Linux Desktop)
#   ./run.sh build-apk        (Compila el APK release para celular)
#   ./run.sh test             (Ejecuta las pruebas unitarias y E2E)
#   ./run.sh analyze          (Ejecuta análisis estático con linter)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# Priorizar JDK 17 si está instalado o el JBR de Android Studio
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
elif [ -d "/usr/lib/jvm/java-21-openjdk-amd64" ]; then
  export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
else
  export JAVA_HOME="${JAVA_HOME:-/home/yoner/.local/share/flatpak/app/com.google.AndroidStudio/current/active/files/extra/jbr}"
fi

export ANDROID_HOME="${ANDROID_HOME:-/home/yoner/Android/Sdk}"
export PATH="$JAVA_HOME/bin:$HOME/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"

ACTION="${1:-auto}"

# 1. Opción para compilar el APK directamente
if [ "$ACTION" = "build-apk" ] || [ "$ACTION" = "apk" ]; then
  echo "▶ Compilando APK Release de Asistencia Uniguajira..."
  flutter build apk --release --android-skip-build-dependency-validation "${@:2}"
  echo "✔ APK generado con éxito en: build/app/outputs/flutter-apk/app-release.apk"
  ls -lh build/app/outputs/flutter-apk/app-release.apk
  exit 0
fi

# 2. Opción para ejecutar tests
if [ "$ACTION" = "test" ]; then
  echo "▶ Ejecutando suite de pruebas unitarias y E2E..."
  flutter test "${@:2}"
  exit 0
fi

# 3. Opción para análisis estático
if [ "$ACTION" = "analyze" ]; then
  echo "▶ Ejecutando análisis estático..."
  flutter analyze --no-pub "${@:2}"
  exit 0
fi

DEVICE="$ACTION"

# Auto-detección si no se especifica dispositivo
if [ "$DEVICE" = "auto" ]; then
  ANDROID_ID=""
  if command -v adb >/dev/null 2>&1; then
    ANDROID_ID=$(adb devices | awk '$2=="device"{print $1}' | head -n 1 || true)
  fi
  if [ -n "$ANDROID_ID" ]; then
    echo "📱 Dispositivo Android detectado automáticamente vía adb: $ANDROID_ID"
    DEVICE="$ANDROID_ID"
  else
    echo "🖥️  No se detectó dispositivo Android por adb. Seleccionando Linux Desktop..."
    DEVICE="linux"
  fi
fi

# Si se especificó explícitamente "android", resolver el ID del dispositivo conectado
if [ "$DEVICE" = "android" ]; then
  DETECTED_DEV=""
  if command -v adb >/dev/null 2>&1; then
    DETECTED_DEV=$(adb devices | awk '$2=="device"{print $1}' | head -n 1 || true)
  fi
  if [ -z "$DETECTED_DEV" ] && command -v flutter >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    DETECTED_DEV=$(python3 -c "
import json, subprocess
try:
    devs = json.loads(subprocess.check_output(['flutter', 'devices', '--machine']))
    android_dev = next((d['id'] for d in devs if 'android' in d.get('targetPlatform', '')), '')
    print(android_dev)
except Exception:
    print('')
" 2>/dev/null || true)
  fi

  if [ -n "$DETECTED_DEV" ]; then
    echo "📱 Dispositivo Android detectado: $DETECTED_DEV"
    DEVICE="$DETECTED_DEV"
  else
    echo "⚠️  No se detectó dispositivo Android específico, intentando target genérico 'android'..."
    DEVICE="android"
  fi
fi

EXTRA_FLAGS="--android-skip-build-dependency-validation"

echo "▶ Ejecutando Asistencia Uniguajira en: $DEVICE"
flutter run -d "$DEVICE" $EXTRA_FLAGS "${@:2}"
