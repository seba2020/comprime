# Plan de implementación — Comprime 0.1 Beta

## Estado y reglas

Entrega actual: seis especificaciones y primera implementación de fases 0/1. Build SwiftPM y comprobaciones del escáner aprobados; pruebas locales de codecs realizadas. Fases 0/1 permanecen parciales por los pendientes de [validación](validation/phase-0-1.md). Las fases 2–7 siguen pendientes. No saltar criterios de salida ni ampliar el alcance sin documentar la decisión.

Progresión: 0 → 1 → 2 → 3 → 4 → 5 → 7. Fase 6 (landing) puede comenzar tras 1 y disponer de captura aprobada; publicar descarga exige 7. El mockup aprobado ya está recuperado y se usa como referencia directa.

## Fase 0 — Viabilidad y fixtures

Objetivo: resolver riesgos técnicos antes de comprometer soporte.

- Confirmar toolchain compatible con macOS 14+ y ejecución Apple Silicon; registrar versiones.
- Probar lectura y escritura real de JPEG, PNG y HEIC/HEIF estáticos; inspeccionar tipos disponibles en runtime.
- Probar WebP con alpha, metadata y quality; decidir adaptador nativo o libwebp y fijar dependencia/licencia.
- Validar variantes HEIF admitidas y detección de animación, HDR y contenido auxiliar no soportado.
- Construir corpus descrito en fixtures/README.md con derechos claros y GPS sintético.
- Medir memoria/tiempo preliminar, fijar límites defensivos de píxeles y concurrencia.
- [x] Recuperar segundo mockup aprobado e incorporarlo con nombre, hash y procedencia en reference/.

Salida: registro de capacidades reproducible, fixtures y riesgos con decisión. Un formato obligatorio pendiente impide declarar beta multiformato, pero no impide continuar trabajo independiente con adaptadores provisionales claramente marcados.

## Fase 1 — Proyecto nativo y escaneo

- Crear proyecto SwiftUI, deployment target macOS 14, arquitectura Apple Silicon, modelos y protocolos.
- Crear inicio, selector de carpeta, sidebar y estado de escaneo progresivo.
- Detectar contenido, bytes, dimensiones, alpha/orientación; thumbnails de memoria limitada.
- Aplicar selección no recursiva, exclusiones y errores por archivo.

Salida: app abre carpeta mixta, muestra inventario correcto y sigue responsive; vacío, permisos, corruptos y cancelación tratados. Compilación real documentada. No anunciar aún compresión funcional.

## Fase 2 — Motor y objetivo

- Implementar estrategias y adaptadores probados en fase 0.
- Búsqueda de quality acotada; PNG lossless; resize; política de auto/conversión.
- Metadata/GPS, color, orientación, alpha y comprobación de candidato completo.
- Calibrar quality mínimo 0,70 y escalas con corpus; documentar cualquier cambio.

Salida: matriz multiformato pasa; objetivo en bytes reales; resultado targetUnmet sin crash; transparencia y fuentes especiales no se pierden; ningún bucle excede presupuesto. Evaluación visual a 100% documentada.

## Fase 3 — Preview e interfaz principal

- Tres muestras por complejidad aproximada desde thumbnails: métrica simple de variación/gradiente, orden determinista y selección de extremos/mediana sin duplicados.
- Preview reducido con etiqueta estimada, verificación completa al necesitar bytes reales/100%.
- Slider compartiendo coordenadas, zoom/pan, inspector y warnings.
- Cache limitada, debounce y descarte de resultados obsoletos.
- [x] Comparar layout con mockup original; continuar con accesibilidad y ventana mínima.

Salida: cambiar ajustes rápidamente nunca muestra resultado viejo como actual; comparación 100% reproduce archivo codificado; controles funcionan con teclado/VoiceOver y la estructura mantiene fidelidad al mockup recuperado.

## Fase 4 — Lote y salida segura

- Concurrencia limitada con backpressure por memoria, snapshot de ajustes y progreso.
- OutputManager con nombres exclusivos, temporales, validación y publicación atómica.
- Cancelación cooperativa, incidencias por archivo y resumen de conjuntos comparables.

Salida: lote mixto termina; hash de todos los originales permanece igual; colisiones y reejecuciones no sobrescriben; cancelar conserva outputs válidos; disco lleno/permiso revocado no publican archivos parciales.

## Fase 5 — Reemplazo con respaldo y recuperación

- Implementar BackupManager, hashes y manifest por ejecución.
- Limitar reemplazo a conservar formato, advertir y confirmar en UI.
- Recuperar/reconciliar estados tras interrupción y documentar restauración.

Salida: inyectar fallo antes/después de backup, validación y reemplazo; siempre existe original íntegro o backup íntegro verificable. Backup fallido impide reemplazo. Cambio externo de fuente aborta esa operación. Nunca usar fotos personales para pruebas destructivas.

## Fase 6 — Landing y despliegue

- Scaffold Next.js + TypeScript + Tailwind, versiones y lockfile.
- Implementar hero, captura auténtica, formatos, privacidad, requisitos y FAQ.
- Hasta release real, CTA «Beta en preparación»; sin descarga simulada.
- Crear/conectar repo GitHub cuando se inicie esta fase; importar directamente en Vercel con raíz apps/landing.
- Verificar preview de Vercel y luego publicación configurada; registrar URLs reales.

Estado: implementación local completa; build de producción aprobado. Repositorio y URL de producción se registran al terminar la publicación.

Salida: tipos/lint/build correctos; móvil y escritorio sin overflow, navegación por teclado y enlaces válidos; sin upload ni trackers. Deploy procede de integración GitHub→Vercel, nunca ChatGPT Sites. No hace falta desplegar la landing para validar motor local.

## Fase 7 — Beta distribuible

- Completar matriz de aceptación en macOS 14 y una versión posterior compatible, Apple Silicon.
- Ensayo de lote grande con memoria/tiempos registrados, cancelación y recuperación.
- Validar privacidad sin conexión; revisar accesos/red y licencias de codecs.
- Firmar/notarizar, probar instalación limpia y generar checksum/release notes.
- Publicar artefacto real y conectar descarga de landing.

Salida: binario verificable, requisitos claros y limitaciones documentadas. No declarar soporte de Intel, animación o variantes HDR no validadas.

## Matriz de aceptación mínima

| Caso | Resultado exigido | Fase |
|---|---|---|
| JPG/JPEG/PNG/HEIC/HEIF/WebP mezclados | Estrategia correcta por contenido | 0, 2, 4 |
| Bajo objetivo, sin cambios requeridos | Copia idéntica, ahorro cero | 2, 4 |
| Objetivo imposible | targetUnmet, sin degradación ilimitada | 2 |
| PNG alpha → JPEG | Bloqueo y alternativa; sin pérdida silenciosa | 2, 3 |
| Metadata y GPS | Conservación/retirada verificada según opción | 2 |
| EXIF rotada y P3 | Orientación/color correctos en salida y preview | 2, 3 |
| Animación/HDR/auxiliares no admitidos | Omitir explicando, no aplanar | 0, 2 |
| Cambios rápidos de ajustes | Solo generación actual visible | 3 |
| 100% con resize | Resultado real y coordenadas coherentes | 3 |
| Dos nombres convergen al convertir | Ambas salidas sin sobrescritura | 4 |
| Disco lleno/cancelación/corrupción | Sin parciales publicados; resumen correcto | 4 |
| Backup falla/fuente cambia/crash | Original o respaldo íntegro | 5 |
| Landing sin release | Ningún enlace de descarga ficticio | 6 |
| Release instalado sin conexión | Compresión funcional local | 7 |

## Próximo bloque de trabajo

Comenzar por fase 0 y estructura de fase 1. El primer informe de implementación debe entregar: versiones verificadas, tabla real de codecs, decisión WebP, fixtures, proyecto que compila y resultados del escaneo. No construir landing y reemplazo avanzado antes de validar bases. No registrar como completadas las fases por mera existencia de archivos vacíos.
