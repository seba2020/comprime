# Especificación de interfaz — Comprime 0.1 Beta

## Referencia principal

El segundo mockup aprobado en «Recorta» es la referencia visual principal y está incorporado como [comprime-approved-mockup-v2.png](reference/comprime-approved-mockup-v2.png). Ver [procedencia, hash y revisión](reference/mockup-reference.md). Las medidas que siguen traducen el mockup a controles macOS reales.

## Lenguaje visual

Utilidad macOS sobria: tipografía del sistema, controles nativos cuando corresponda, iconografía SF Symbols, espacio en blanco, bordes suaves y jerarquía clara. Teal en acciones, selección y divisor; no colorear toda la interfaz.

| Token | Valor |
|---|---|
| Accent | #0F766E |
| Accent hover/pressed | #115E59 |
| Accent soft | #CCFBF1 |
| Background | #F7F7F5 |
| Surface | #FFFFFF |
| Text | #171717 |
| Secondary | #737373 |
| Border | #E5E5E5 |

Propuesta inicial: espaciado 8/12/16/24, radios 8–12 pt, cuerpo 13 pt, títulos 20–24 pt. Validar contraste y legibilidad; el texto secundario pequeño puede necesitar oscurecerse sobre fondos no blancos. Paleta clara como referencia; adaptar colores semánticos para modo oscuro sin invertir fotos ni alterar su perfil.

## Pantalla principal

Propuesta: ventana inicial 1280 × 820 pt; ancho mínimo 1024 pt, altura mínima 680 pt. Tres zonas redimensionables, con scroll independiente cuando sea necesario:

- Sidebar (~240 pt): carpeta, ruta truncada con detalle accesible, total/promedio, formatos y lista con thumbnail, nombre, extensión y bytes.
- Centro flexible: selección de muestra, comparador grande y métricas.
- Inspector (~280 pt): objetivo por imagen, formato de salida, destino, opciones avanzadas y CTA principal.

Evitar superponer ajustes sobre la imagen. Nombres largos se truncan visualmente, conservando acceso al nombre completo. No ocultar errores ni CTA al reducir ventana.

## Comparador

Original a izquierda, Comprimida a derecha; división vertical arrastrable. Ambas capas comparten encuadre, orientación, zoom y desplazamiento. Fondo ajedrezado para transparencia. Fit, 100% y zoom manual accesibles por teclado. En 100%, un píxel de imagen equivale a un píxel físico de pantalla, considerando escala Retina; mostrar referencia de zoom cuando salida tiene menor resolución.

Métricas: tamaño original → resultado, ahorro %, dimensiones antes/después, formato antes/después, y quality en detalle técnico cuando aplique. PNG lossless muestra «Sin pérdida», no un quality inventado. El valor del encoder no debe convertirse en una etiqueta «Calidad excelente» ni promedio entre codecs.

Preview rápido: etiqueta «Estimación», nunca prometer bytes finales a partir de la miniatura. Verificación: mostrar «Calculando resultado…» y luego bytes reales del candidato completo. El zoom 100% usa el resultado codificado completo decodificado, no un recorte recodificado que simule el resultado. Si el codec no permite lectura regional, mantener límites de memoria y explicar demora.

Tres thumbnails «Muestra 1/2/3» con nivel simple/medio/complejo aproximado. Con una o dos imágenes, mostrar solo las disponibles. Selección manual desde sidebar. Los cambios cancelan previews obsoletos; no parpadear con resultados de la configuración anterior.

## Ajustes y textos

- «Objetivo por imagen»: presets y campo personalizado con unidad KB/MB.
- «Formato de salida»: Mantener original / Optimizar automáticamente / Convertir todas a…
- «Se guardarán en Comprimidas. Tus originales se conservan.»
- «Opciones avanzadas»: metadata, eliminar GPS, permitir reducción de resolución, reemplazo con backup.
- Transparencia a JPEG/HEIC no soportada: «Este formato no conserva la transparencia. Elige PNG o WebP.» Beta bloquea esos archivos; no incorpora aplanado con fondo implícito.
- Reducción: «Se reducirá de 6000 × 4000 a 4800 × 3200 para intentar alcanzar el objetivo.»
- Fuera de objetivo: «No se pudo alcanzar 1 MB con los límites de calidad y resolución.»
- CTA dinámico: «Comprimir 83 fotos», usando elegibles, no archivos totales.

## Estados

| Estado | Contenido y acción |
|---|---|
| Inicio | Nombre, mensaje local, Abrir carpeta |
| Analizando | Conteo progresivo, Cancelar |
| Vacía/no compatible | Explicación, Abrir otra carpeta |
| Lista | Ajustes, muestras, CTA si existen elegibles |
| Preview en curso | Indicador local, resto de UI usable |
| Advertencia | Razón, formato alternativo o configuración necesaria |
| Procesando | 32/83, porcentaje, archivo actual, ahorro validado, Cancelar |
| Cancelando | No programar nuevos trabajos; esperar puntos seguros |
| Terminado | Resumen y Abrir carpeta de salida |
| Parcial/cancelado | Resultados preservados e incidencias |
| Error de carpeta | Acción concreta: reautorizar acceso/elegir destino/reintentar |

Durante lote, congelar objetivo/formato y desactivar inicio duplicado. Cerrar ventana con trabajo activo ofrece continuar o cancelar de forma segura. Reemplazo de originales requiere confirmación específica en la app, mostrando ubicación del backup y restricciones.

## Accesibilidad

Orden de foco lógico; ⌘O abre carpeta; Escape cancela operación activa mediante transición segura. Enter solo activa acción enfocada y nunca reemplazo destructivo accidental. Divisor accesible con flechas y valor porcentual; labels de VoiceOver; estado comunicado con texto además de color. Respetar Reduce Motion y tamaños de texto. Anunciar progreso de forma moderada, sin leer cada actualización de bytes.

## Landing

Next.js + TypeScript + Tailwind en apps/landing. Diseño consistente con la app, adaptable desde móvil hasta escritorio. Hero: «Comprime fotos sin complicarte.» Subtítulo: «Dile cuánto deben pesar. Comprime encuentra la mejor calidad posible.» Mensaje: «Tus fotos no salen de tu Mac.» Enumerar formatos concretos junto al tagline para evitar prometer todos los formatos existentes.

Secciones: hero + captura aprobada; flujo elegir carpeta/objetivo/preview/comprimir; formatos y transparencia; privacidad y salida segura; requisitos macOS 14+ Apple Silicon; descarga beta y FAQ. Sin upload, cuentas, formularios innecesarios, trackers ni testimonios/benchmarks inventados.

Mientras no exista binario firmado: «Beta en preparación», sin enlace falso de descarga. Al publicar: CTA a artefacto real de release, versión, requisitos y checksum. No afirmar distribución gratuita/open source sin decisión explícita para Comprime. La landing puede ser pública; el procesamiento sigue ocurriendo exclusivamente en la app.

Desplegar importando el repositorio GitHub en Vercel, con Root Directory apps/landing. PRs generan previews; rama de producción se configura al crear repositorio. No ChatGPT Sites. La captura final debe mostrar la app compilada y conservar la composición del mockup aprobado.
