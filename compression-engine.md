# Motor de compresión — Comprime 0.1 Beta

## Contrato

Entrada: ImageAsset validado + CompressionRequest inmutable. Salida: CompressionResult con candidato temporal validado, bytes reales, dimensiones, formato, quality opcional, advertencias, cumplimiento y motivo de fallo. El motor no reemplaza originales ni escribe en destinos finales: eso corresponde a OutputManager.

El objetivo es elegir el mejor candidato probado, no demostrar un óptimo perceptual universal. La calidad numérica de un encoder no es comparable directamente con la de otro.

## Componentes

- ImageDecoder: inspección de contenido, dimensiones, frames, alpha efectivo, orientación, color y metadata.
- ImageEncoder: capacidades y codificación; implementación nativa donde se valide y adaptador WebP si hace falta.
- FormatStrategy: JPEGStrategy, PNGStrategy, HEICStrategy, WebPStrategy.
- TargetSizeOptimizer: búsqueda acotada y evaluación por bytes.
- ImageResizer: resize desde el original decodificado, nunca desde un candidato ya degradado.
- CompressionEngine: selecciona estrategia y construye resultado tipado.

JPEG/JPG son aliases de una familia. HEIC/HEIF se inspecciona como contenedor: conservar formato significa conservar familia y capacidades admitidas, no prometer bitstream idéntico. Un HEIF con codec no admitido se informa, no se reetiqueta con otra extensión. Al convertir, extensión y tipo real deben coincidir.

## Estrategias

| Familia | Primer intento | Si no cumple | Alpha |
|---|---|---|---|
| JPEG | Buscar quality a resolución original | Resize gradual + nueva búsqueda | No |
| HEIC/HEIF compatible | Buscar quality con encoder verificado | Resize gradual + nueva búsqueda | No asumir soporte en beta |
| WebP estático | Quality por adaptador; lossless cuando corresponda | Resize o nuevo candidato permitido | Conservar y comprobar |
| PNG | Recodificación/optimización lossless, comprobar píxeles y metadata | Resize si autorizado; conversión solo en auto o conversión explícita | Conservar |

PNG no tiene quality JPEG. Si la optimización lossless no reduce peso, conservar original antes de degradar o convertir innecesariamente. Cualquier reducción de resolución deja de ser lossless a nivel de imagen; la UI debe aclararlo.

La fase 0 valida lectura/escritura nativa y control de quality real en macOS mínimo. Usar ImageIO/Core Image como primera opción. WebP se abstrae desde el inicio para integrar libwebp si se necesita; fijar versión, licencia y forma de empaquetado una vez probadas. No suponer aceleración por hardware ni soporte por extensión.

## Búsqueda de quality

Parámetros iniciales propuestos, sujetos a corpus de pruebas: quality mínimo 0,70 y máximo 1,00 para la abstracción normalizada; adaptar rango al encoder. Resolución de búsqueda 0,01. Probar extremos y realizar hasta 7 pasos de búsqueda binaria más hasta 2 comprobaciones vecinas: máximo 11 codificaciones por nivel de resolución. PNG no usa este presupuesto de quality.

1. Comprobar cancelación, capacidades y límites de dimensiones/memoria antes de decodificar.
2. Si el original cumple y no requiere conversión ni limpieza de metadata, reutilizar sus bytes.
3. Codificar máximo. Si cumple, seleccionarlo.
4. Codificar mínimo. Si cumple, buscar entre ambos extremos y conservar todos los candidatos válidos necesarios, al menos el de mayor quality probado que cumple.
5. Si el mínimo no cumple, pasar al siguiente nivel de resolución autorizado. No seguir bajando quality indefinidamente.
6. Medir el archivo completo incluyendo metadata aplicada, no solo el stream de píxeles.
7. Revalidar candidato final antes de entregarlo.

La relación tamaño/quality puede tener irregularidades. Conservar el mejor candidato ya comprobado; ante no monotonicidad, usar comprobaciones vecinas dentro del presupuesto. Nunca devolver nil forzado ni suponer que la última prueba es la mejor. Un resultado que supera el objetivo por un byte no cumple.

Prioridad dentro de un formato: primer nivel de resolución que alcanza objetivo, luego mayor quality probado. Si ningún candidato cumple, elegir mejor resultado seguro según resolución/calidad y reducción real, marcándolo como fuera de objetivo. No etiquetar como «máxima calidad posible» una garantía matemática.

## Reducción de resolución

Parámetros propuestos: escalas lineales 1,00; 0,90; 0,80; 0,70; 0,60; 0,50. Aplicar siempre al original, preservar proporción, redondear a dimensiones válidas del encoder y nunca ampliar. Límite inicial adicional: no reducir lado largo por debajo de min(lado largo original, 1280 px); detener si se alcanza el límite. Validar estos valores con fotos reales, gráficos y texto en fase 2.

Cada escala reinicia búsqueda de quality. Presupuesto total duro: seis niveles, máximo 66 codificaciones por formato para estrategias con quality. Cancelación entre intentos. No es una promesa de latencia; registrar tiempo y memoria y ajustar presupuesto con evidencia.

Si el usuario desactiva resize, solo se prueba resolución original. Si no se cumple bajo los límites, retornar targetUnmet; no escalar hasta miniaturas para declarar éxito.

## Selección de formato

Mantener original: una sola familia, sin conversión encubierta.

Conversión explícita: familia elegida, salvo incompatibilidad que bloquee el archivo. Para alpha efectivo, JPEG y el camino HEIC de beta se bloquean; proponer PNG/WebP. No aplanar automáticamente ni añadir elección de fondo en 0.1.

**Regla automática propuesta para beta:** probar primero formato original. Si cumple, conservarlo. Si no cumple, probar como máximo una alternativa a resolución original antes de reducir resolución: WebP para PNG/WebP con alpha; JPEG para PNG opaco; WebP para JPEG/HEIC opacos. Después probar escalas autorizadas, primero original y luego alternativa. Detener al primer nivel con candidato válido; preferir original cuando ambos cumplen. Si variante no soportada, informar y no convertir contenido complejo. HEIC sigue disponible mediante conservación y conversión explícita; ampliar preferencias automáticas requerirá corpus comparativo.

Esta regla limita a dos familias y evita cambiar por unos KB cuando original ya cumple. No pretende comparar calidad perceptual mediante quality numérico. Presupuesto máximo de auto: 132 codificaciones con búsqueda; telemetría de desarrollo solo local, nunca analítica enviada.

## Color, orientación y metadata

- Aplicar orientación una vez y actualizar etiqueta al escribir; no duplicar rotaciones.
- Mantener perfil de color compatible; si se requiere conversión, transformar píxeles de forma gestionada y advertir. No quitar ICC dejando píxeles interpretados incorrectamente.
- Mantener metadata representable es el default; actualizar dimensiones/orientación y no copiar thumbnails obsoletos.
- «Eliminar metadata» retira campos descriptivos/EXIF/IPTC/XMP, GPS y thumbnails que los contengan; conservar la información técnica necesaria para interpretar correctamente color/orientación.
- «Eliminar GPS» retira coordenadas y ubicación conocida en EXIF/XMP/IPTC; validar con fixtures. Si no puede verificarse eliminación, fallar esa transformación, no declararla hecha.
- No prometer preservar HDR, gain maps, profundidad, múltiples frames ni imágenes auxiliares sin soporte probado. Beta omite estos contenidos si se perderían silenciosamente.

## Preview y cache

Preview rápido de lado largo propuesto 1600 px, con debounce de 200 ms: sirve para interacción y selección, no para inferir bytes finales. Verificación de la muestra usa motor completo; mostrar bytes reales solo al acabar. El CTA puede estar disponible con muestras no verificadas, pero sin presentar ahorro del lote como real.

Para 100%, generar o reutilizar candidato completo, decodificar y mostrar región visible. Recodificar un crop independiente no reproduce artefactos ni tamaño del archivo final y no es válido como comparación final.

Cache por identidad de archivo + tamaño/fecha + hash cuando necesario, orientación, perfil, objetivo, formato, metadata, resize, versión del motor/encoder y tipo de preview. Cambiar ajustes invalida candidatos afectados. Cancelación cooperativa y generation token impiden publicar resultados atrasados. Cache con límite de bytes y expulsión LRU; temporales solo locales y limpiados al cerrar/recuperar sesión.

## Errores y pruebas

Errores tipados: unsupportedContent, unreadable, changedSource, invalidTarget, insufficientMemory, encodeFailed, targetUnmet, incompatibleTransparency, metadataFailure, cancelled. Los errores de destino pertenecen al sistema de archivos.

Corpus mínimo: JPEG simple/detallado, PNG alpha/opaque, HEIC y HEIF compatibles, WebP alpha/opaque, ya bajo objetivo, corrupto, extensión incorrecta, orientaciones EXIF, Display P3/ICC, GPS, animación, fuente modificada y límite imposible. Probar bytes finales incluyendo metadata, límites de bucle, alpha, dimensiones, orientación y cancelación. Evaluación visual a 100% para fotos, pelo/hojas, gradientes, texto y bordes; no usar solo tamaño como calidad.
