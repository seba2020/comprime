# Comprime 0.1 Beta

**Mismas fotos. Menos peso. Cualquier formato.**

Paquete de especificaciones para implementar una utilidad nativa macOS que reduce carpetas mixtas de imágenes a un objetivo de peso por archivo. Fecha: 18 de septiembre de 2026. Idioma inicial: español.

## Estado real de la entrega

MVP 0.1 Beta funcional disponible: app SwiftUI con modos Sistema/Claro/Oscuro, preview Original/Comprimida, objetivo por imagen, motor multiformato y procesamiento por lote con salida segura. La landing Next.js incluye descarga, contacto por X y Vercel Web Analytics. Ver [validación del MVP](validation/mvp-0.1.md).

- Sitio de producción: https://comprime-two.vercel.app/
- Repositorio público: https://github.com/seba2020/comprime
- Contacto: https://x.com/Sebahhgg
- Paquete público: https://comprime-two.vercel.app/Comprime-0.1-Beta-macOS-Apple-Silicon.zip

El **segundo mockup aprobado** está recuperado y versionado en [reference/comprime-approved-mockup-v2.png](reference/comprime-approved-mockup-v2.png). La procedencia, hash y revisión de fidelidad están en [reference/mockup-reference.md](reference/mockup-reference.md).

## Leer en este orden

1. [Producto y alcance](product-spec.md)
2. [Interfaz y landing](ui-spec.md)
3. [Motor de compresión](compression-engine.md)
4. [Arquitectura y seguridad](architecture.md)
5. [Plan por fases y aceptación](implementation-plan.md)

## Decisiones que se mantienen

- macOS 14+, Apple Silicon, Swift + SwiftUI; procesamiento local, sin cuenta, backend, anuncios ni analítica.
- Entrada JPG/JPEG, PNG, HEIC/HEIF y WebP en una misma carpeta.
- Objetivo por imagen: 500 KB, 1 MB, 2 MB, 5 MB o personalizado.
- Mantener formato por defecto; optimización automática y conversión explícita disponibles.
- Comparador Original/Comprimida, tres muestras, Fit, 100% y zoom manual.
- Originales intactos por defecto; carpeta Comprimidas; reemplazo avanzado solo con respaldo verificado.
- Estética macOS minimalista, acento teal #0F766E.
- Landing Next.js + TypeScript + Tailwind, repositorio GitHub importado directamente a Vercel. No usar ChatGPT Sites.

## Estructura preparada

```text
comprime/
  README.md
  product-spec.md
  ui-spec.md
  compression-engine.md
  architecture.md
  implementation-plan.md
  reference/mockup-reference.md
  apps/macos/README.md
  apps/landing/README.md
  fixtures/README.md
  .gitignore
```

El monorepo coordina app, landing y documentación. `apps/macos` contiene la aplicación y sus comprobaciones; `apps/landing` contiene la landing de producción en Next.js, TypeScript y Tailwind.

## Fuente y precedencia

Fuente: conversación «Recorta», ID 6aac9e13-8f14-83e9-8cfa-5f0b2bf97222, recuperada con sus decisiones finales. Prevalece el pedido actual, luego la especificación final y la aprobación del segundo mockup; las ideas tempranas de soportar solo JPEG o quality mínimo 40/75 quedaron superadas.

Los detalles nuevos aparecen como **decisiones de implementación propuestas** o **parámetros iniciales a validar**. No se presentan como acuerdos históricos. Las capacidades concretas de codecs y versiones de dependencias se verifican en fase 0; este paquete no declara esa validación realizada.

## Estado de distribución

La primera beta está compilada, firmada localmente, empaquetada y publicada desde un repositorio público. El ZIP servido por Vercel tiene SHA-256 `ec44406b09fc5b1077f4f0e5fc3c58c45004f43f5ac85a254e60375131fe1104` y pasó la comprobación de integridad. La app todavía no utiliza certificado Developer ID ni notarización de Apple; la landing explica el paso de apertura manual requerido por macOS.
