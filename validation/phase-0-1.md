# Avance de fases 0 y 1 — 18 septiembre 2026

## Entregado y comprobado

- Paquete Swift macOS 14+ con app SwiftUI, biblioteca ComprimeCore, prueba CodecProbe y ejecutable SmokeChecks.
- Proyecto Comprime.xcodeproj preparado, sintaxis validada con plutil. Su build en Xcode no está probado porque Xcode completo no está instalado.
- Build Swift Package Manager exitoso en arm64 con Swift 6.3.2, macOS 26.5.1 (25F80), Command Line Tools. La primera compilación tardó 48,84 s; incremental posterior 1,50 s. Son tiempos locales de compilación, no rendimiento del motor.
- App local abrió y mostró pantalla inicial, selector de carpeta y diálogo de ruta. Automatización del selector interrumpida por control de la superficie; no se certifica todavía el recorrido UI completo de carpeta hasta inventario. El escáner subyacente sí pasó la carpeta mixta.
- 11 comprobaciones ejecutables correctas: [salida](smoke-checks.txt). Incluyen detección por contenido, alpha/dimensiones, límites, corruptos, exclusiones, vacío, fuentes intactas y carpeta mixta.
- Suite XCTest preparada. `swift test` no pudo ejecutarla: módulo XCTest ausente en Command Line Tools. No se registra como aprobada.

## Codecs: evidencia local, no certificación de macOS 14

| Familia | Lectura | Escritura | Evidencia |
|---|---|---|---|
| JPEG | Real, correcta | ImageIO correcta | q70: 61.935 B; q95: 74.805 B |
| PNG | Real, correcta | ImageIO correcta | 7.555 B con ambos valores de quality; no quality JPEG |
| HEIC | Real, correcta | ImageIO correcta | q70: 1.842 B; q95: 2.233 B |
| HEIF genérico | Anunciada por ImageIO | No anunciada como public.heif | No hay fixture de otro codec HEIF |
| WebP | Real, correcta en escáner | No nativa en ImageIO | cwebp/libwebp 1.6.0 generó fixtures y dwebp los decodificó |

Datos completos: [native-codecs.json](../fixtures/generated/native-codecs.json). Las pruebas de HEIC fallaron dentro del sandbox de la herramienta por acceso a servicios gráficos; la misma prueba local fuera de ese sandbox tuvo roundtrip correcto. Esto no valida todavía la app con App Sandbox de distribución.

`heic-container.heif` es una copia del contenedor HEIC con extensión .heif para demostrar detección por contenido. **No** es prueba de todos los codecs HEIF. Los quality probados corresponden a una sola imagen sintética; no son validación perceptual ni búsqueda por objetivo.

## Decisión WebP

Usar un adaptador de libwebp para escritura, con 1.6.0 como versión candidata comprobada localmente. La instalación de desarrollo vive en Homebrew; la app entregada no enlaza a ella ni ejecuta cwebp. Antes de fase 2 completa: incorporar biblioteca de forma reproducible, licencia y notices, fijar hash/version y probar alpha/metadata. No distribuir una app que requiera Homebrew.

## Límites iniciales implementados

Escaneo no recursivo. Máximo 250 MB por archivo y 80 millones de píxeles antes de decodificar miniatura. Miniaturas hasta 96 px y 24 MB acumulados de datos codificados; si se agota el presupuesto, mantener inventario sin thumbnail. Estos límites no constituyen benchmark de memoria: queda medir pico residente y fijar presupuesto del motor antes de compresión. UI informa canal alpha, no afirma haber medido alpha efectivo píxel a píxel.

## Pendientes concretos

Fase 0 sigue parcial: matriz en macOS 14, alpha y metadata en todos los codecs, HDR/auxiliares, corpus fotográfico, medición de memoria/estrés, empaquetado libwebp y mockup original. La inspección actual inventaría archivos estáticos; no equivale todavía a elegibilidad final de compresión frente a HDR o auxiliares.

Fase 1 tiene implementación compilada y escáner comprobado. Falta completar prueba UI de carpeta/cancelación/errores y compilar proyecto desde Xcode. La app permite analizar, no comprimir; no muestra botón funcional ficticio de compresión. No hay salida, backup, lote ni landing implementados.

## Reproducción

Con herramientas Swift: ejecutar scripts/build-local.sh y scripts/check-local.sh desde el repo. En entorno con sandbox anidado restrictivo, la sesión utilizó `--disable-sandbox` exclusivamente para el sandbox interno de SwiftPM y redirigió caches al workspace; no se requiere cambiar protecciones del sistema. El build habitual no usa ese flag.

Con Xcode completo: abrir apps/macos/Comprime.xcodeproj para app o Package.swift para paquete y tests. Seleccionar firma/equipo antes de distribución. El identificador local.comprime.beta es provisional de desarrollo.

App de prueba local: ../Comprime.app respecto de la raíz del proyecto entregado. Firma ad hoc de desarrollo, no notarizada ni release pública.
