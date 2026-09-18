# Validación del MVP 0.1 Beta

Fecha: 18 de septiembre de 2026.

## Funcionalidad entregada

- App macOS nativa con estilo minimalista y acento teal.
- Carpetas mixtas JPEG/JPG, PNG, HEIC/HEIF compatible y WebP estático.
- Objetivos 500 KB, 1 MB, 2 MB, 5 MB y personalizado.
- Mantener formato, optimización automática y conversión a JPEG, PNG, HEIC o WebP.
- Búsqueda de calidad desde 70%, seguida por reducción gradual de resolución cuando es necesaria.
- Preview real Original/Comprimida con slider, Fit, 50%, 100% y 200%.
- Tres muestras automáticas y selección manual desde la lista.
- Lotes con hasta dos trabajos, progreso, cancelación y resumen.
- Salida exclusiva `Comprimidas`, `Comprimidas-2`, etc.; no sobrescribe resultados previos.
- Reemplazo avanzado únicamente al mantener formato, con respaldo independiente verificado por SHA-256.
- Metadata compatible, retiro de GPS y protección frente a alpha, múltiples frames, HDR/profundidad y cambios externos.
- libwebp 1.6.0 integrado estáticamente, recompilado con deployment target macOS 14. Licencia BSD incluida.

## Evidencia

La batería EngineChecks pasó completamente con fixtures sintéticos:

- JPEG alcanzó 600 KB usando bytes del archivo final y quality 82, con resize 1600×1200 → 1280×960.
- Un objetivo imposible produjo advertencia y no degradó sin límites.
- Archivos ya bajo objetivo conservaron exactamente sus bytes.
- Conversión y roundtrip correctos para JPEG, PNG, HEIC y WebP.
- GPS ausente en los cuatro formatos transformados.
- PNG transparente → WebP conservó alpha; PNG transparente → JPEG fue bloqueado.
- Orientación EXIF fue aplicada una vez.
- Lote mixto escribió todos los resultados y conservó hashes de originales.
- Colisiones de nombres y ejecuciones repetidas no sobrescribieron archivos.
- Cancelación previa no publicó salidas pendientes.
- Reemplazo avanzado produjo respaldo idéntico al original y salida comprimida diferente.

SmokeChecks también pasó sus 11 comprobaciones de inventario, límites, corruptos y originales intactos.

La app firmada ad hoc pasó verificación estricta y el ZIP final pasó la prueba de integridad. SHA-256 del ZIP: `ec44406b09fc5b1077f4f0e5fc3c58c45004f43f5ac85a254e60375131fe1104`.

## Recorrido visual comprobado

La app abrió, analizó una carpeta de seis imágenes (JPEG, PNG, HEIC y WebP), generó preview JPEG `2,2 MB → 993 KB` con quality 75 y completó el lote `11 MB → 7,5 MB`, ahorro 3,6 MB. Cuatro de seis imágenes cumplieron el objetivo de 1 MB; las otras quedaron identificadas como fuera de objetivo.

## Límites conocidos

- Build de desarrollo firmado ad hoc; no está notarizado para distribución pública.
- Se compiló y probó en macOS 26 arm64. libwebp se construyó para macOS 14, pero falta ejecutar la app completa en un equipo macOS 14 real.
- HEIF se admite cuando ImageIO puede decodificar su codec; la salida HEIF se normaliza a HEIC.
- Animaciones, HDR, profundidad, gain maps y más de 8 bits se omiten para evitar pérdida silenciosa.
- Metadata propietaria o XMP no representable puede omitirse; la UI lo comunica.
- No hay todavía actualización automática, firma Developer ID ni notarización.
- El segundo mockup aprobado fue recuperado; la app ya incorpora su paleta clara, encabezado, estructura de tres zonas e identidad visual oscura/teal.
- El icono final usa fondo carbón y símbolo teal de compresión, en la misma familia visual de Recorta.
- La apariencia puede seguir al sistema o fijarse en Claro/Oscuro desde el encabezado.
- La landing compila como contenido estático e integra Vercel Web Analytics, descarga directa y enlace de contacto por X.

## Ejecutar

Abrir `Comprime.app`. Por defecto siempre escribe en una carpeta nueva y conserva originales. Para desarrollo, `scripts/check-local.sh` valida el escáner y `EngineChecks` valida el motor con fixtures sintéticos.
