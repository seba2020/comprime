# Comprime macOS — primera implementación

SwiftUI + ComprimeCore, macOS 14+, Apple Silicon. MVP funcional: análisis, preview Original/Comprimida, objetivo por imagen, motor JPEG/PNG/HEIC/WebP, lote, salida segura y respaldo avanzado.

## Compilar

Desde raíz del proyecto: `scripts/build-local.sh`. Ejecutable en `.build-cache/build/debug/Comprime`.

Proyecto Xcode preparado: `Comprime.xcodeproj`. También puede abrirse `Package.swift`. Xcode completo no está instalado en el entorno de esta entrega: el build validado es Swift Package Manager.

## Verificar

`scripts/check-local.sh` ejecuta comprobaciones sin XCTest. `EngineChecks` valida el motor, lotes y respaldos con fixtures sintéticos. Con Xcode completo, ejecutar `swift test` desde este directorio para la suite XCTest. [Resultados y límites reales](../../validation/mvp-0.1.md).

CodecProbe genera imágenes sintéticas y mide roundtrips ImageIO; no usarlo sobre carpetas de fotos personales porque escribe fixtures con nombres deterministas. SmokeChecks crea temporales propios y compara originales antes/después.
