# Especificación de producto — Comprime 0.1 Beta

## Problema y resultado

Una persona tiene una carpeta de fotos de varios MB y necesita archivos de hasta 1 MB, o un límite similar, sin configurar codecs. Comprime busca el mejor candidato probado que cumple el límite respetando calidad, resolución y capacidades. No promete compresión imperceptible ni cumplimiento para cualquier imagen.

Ejemplo ilustrativo: 5,8 MB → 943 KB, ahorro aproximado 84%. Los ejemplos no son benchmarks ni resultados de la implementación.

## Plataforma y límites de alcance

Aplicación nativa macOS 14+ para Apple Silicon, Swift/SwiftUI. Sin runtime Python distribuido. Toda lectura, preview, codificación y escritura ocurre localmente. Sin cuentas, backend, analítica, anuncios, carga de fotos ni procesamiento remoto.

Incluye imágenes estáticas JPG/JPEG, PNG, HEIC/HEIF y WebP. La extensión no basta: inspeccionar contenido y capacidades de decodificación. HEIF es un contenedor; no se promete aceptar todos sus codecs, secuencias, profundidad o imágenes auxiliares. No aplanar animaciones ni eliminar contenido auxiliar silenciosamente: informar y omitir en beta si no puede conservarse. TIFF, AVIF, PDF, edición, recorte, filtros, cloud, sincronización e IA generativa quedan fuera.

## Recorrido principal

1. Abrir carpeta local mediante selector del sistema.
2. Analizar archivos y mostrar cantidad, peso total/promedio, formatos, dimensiones, transparencia y thumbnails progresivos.
3. Elegir objetivo por imagen y modo de salida.
4. Comparar muestras Original/Comprimida; seleccionar cualquier archivo de la lista si se desea.
5. Confirmar configuración pulsando «Comprimir N fotos».
6. Procesar con concurrencia limitada; progreso y cancelación disponibles.
7. Mostrar resumen, incidencias y acceso a carpeta de salida.

## Configuración

| Campo | Valor inicial | Comportamiento |
|---|---|---|
| Objetivo | 1 MB | Presets 500 KB, 1 MB, 2 MB, 5 MB y personalizado |
| Formato | Mantener original | No convertir en este modo |
| Optimizar automáticamente | Opcional | Elegir entre candidatos autorizados por reglas del motor |
| Convertir todas a | Opcional | JPEG, PNG, HEIC o WebP |
| Resolución | Conservar primero | Reducción gradual solo si es necesaria; aviso visible |
| Metadata | Mantener | Conservar la representable, advertir pérdidas |
| Eliminar GPS | Desactivado | Retirar ubicación también de metadata anidada y previews |
| Salida | Comprimidas/ | Nunca sobrescribir resultados existentes |
| Reemplazar originales | Desactivado | Respaldo verificado antes de cada reemplazo |

**Decisiones de implementación propuestas:** unidades decimales, 1 KB = 1.000 bytes y 1 MB = 1.000.000 bytes. Cumplimiento definido por bytes reales ≤ objetivo; el redondeo visual no decide. Personalizado positivo y finito, con conversión segura a Int64 y error de validación ante overflow. No imponer un mínimo comercial arbitrario: límites imposibles producen «No alcanzó objetivo».

Solo un comportamiento equilibrado en beta; no agregar selectores Máxima calidad/Más pequeña todavía. La reducción de resolución necesaria se informa en preview y resultados. Se propone un interruptor avanzado «Permitir reducir resolución», activo inicialmente, para poder impedirla.

## Carpeta y elegibilidad

**Decisión propuesta:** escanear solo archivos del primer nivel en 0.1; mostrar «No incluye subcarpetas». No seguir enlaces simbólicos, paquetes ni archivos ocultos. Excluir Comprimidas, salidas de ejecuciones previas y .comprime-backups. Si la carpeta está vacía o solo tiene no compatibles, mostrar explicación y permitir elegir otra; no habilitar compresión.

Registrar fallos de lectura individualmente. Cancelar escaneo deja la pantalla en estado estable. Los archivos ya bajo objetivo se copian sin recodificar si formato y metadata no requieren cambios. La copia sigue figurando como salida, sin ahorro inventado.

## Política de resultados

Estado por archivo: pendiente, procesando, comprimida, sin cambios, no alcanzó objetivo, omitida, no compatible, error o cancelada. Separar estado de procesamiento de cumplimiento del objetivo y existencia de salida.

Una imagen fallida no detiene el lote. «No alcanzó objetivo» puede conservar el mejor candidato seguro disponible, siempre identificado como fuera del límite; si no mejora el original, copiar original en modo conservar/auto y avisar. En conversión explícita se permite crecimiento porque el cambio de formato es solicitado; el aumento debe verse.

La app nunca muestra un archivo como exitosamente guardado antes de validar y publicar su salida. Un archivo fuente modificado desde el escaneo se marca como cambiado y requiere reanálisis antes de procesarlo.

## Resumen

Mostrar total examinado, procesado, copiado sin cambios, fuera de objetivo, omitido, fallido y cancelado; conteos sin doble contabilización. Mostrar además cuántas salidas cumplen objetivo.

Antes/después/ahorro comparan exactamente los mismos archivos con salida válida. Los que no generaron salida quedan fuera del cálculo y se explicitan. Ahorro = suma(bytes originales − bytes de salida); puede ser negativo en conversión. El progreso se calcula por archivos resueltos, no como porcentaje estimado del tiempo.

Acciones: «Abrir carpeta de salida», «Ver incidencias» y «Abrir otra carpeta». Si se canceló, título «Compresión cancelada» con resultados parciales conservados.

## Criterios de aceptación del producto

- Una carpeta mixta procesa todos los formatos estáticos exigidos o explica específicamente la variante no compatible.
- Objetivo y tamaño final son verificables por archivo, sin resultados estimados presentados como definitivos.
- Preview y lote usan misma configuración congelada y mismas reglas.
- No hay pérdida silenciosa de alpha, orientación, color ni metadata que se prometió conservar.
- Originales permanecen idénticos en modo predeterminado, incluso al cancelar o fallar.
- La app funciona sin conexión; la landing no recibe imágenes.
