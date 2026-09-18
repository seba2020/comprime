# Arquitectura — Comprime 0.1 Beta

## Separación de productos

Monorepo propuesto: apps/macos para app Swift/SwiftUI y apps/landing para Next.js/TypeScript/Tailwind. Comparten documentación, identidad y capturas; la web no importa el motor ni procesa/sube imágenes. GitHub aloja código; Vercel importa el repo y construye exclusivamente apps/landing.

La app apunta a macOS 14+ Apple Silicon. ImageIO/Core Image son candidatos nativos sujetos a verificación; WebP usa un adaptador intercambiable. No backend de compresión, cuentas, analítica ni runtime Python.

## Organización objetivo de la app

```text
apps/macos/
  Comprime.xcodeproj/              # preparado; build Xcode pendiente
  Comprime/
    App/ComprimeApp.swift
    Models/{ImageAsset,ImageFormat,CompressionRequest,CompressionResult}.swift
    Compression/{CompressionEngine,TargetSizeOptimizer,ImageResizer}.swift
    Compression/Strategies/{JPEGStrategy,PNGStrategy,HEICStrategy,WebPStrategy}.swift
    Compression/Codecs/{ImageDecoder,ImageEncoder}.swift
    Preview/{PreviewGenerator,PreviewCache}.swift
    Batch/{BatchProcessor,BatchProgress}.swift
    FileSystem/{FolderScanner,OutputManager,BackupManager}.swift
    ViewModels/CompressionViewModel.swift
    Views/{MainView,SidebarView,ComparisonView,CompressionSettingsView}.swift
    Views/{BatchProgressView,CompletionView}.swift
  ComprimeTests/
  ComprimeUITests/
```

Nombres son guía de responsabilidad, no archivos implementados. Evitar nombrar la vista propia ProgressView para no confundirla con SwiftUI.ProgressView.

## Flujo de datos y aislamiento

SwiftUI → CompressionViewModel (@MainActor) → FolderScanner / PreviewGenerator / BatchProcessor → CompressionEngine → estrategia + decoder/encoder. CompressionEngine produce temporal validado → OutputManager publica salida; BackupManager interviene solo para reemplazo.

MainActor mantiene exclusivamente estado de UI. Escaneo, decodificación y escritura fuera del hilo principal. BatchProcessor y PreviewCache controlan recursos mediante actores; encoders no Sendable no se comparten sin aislamiento. Resultados cruzan límites mediante valores seguros, URLs temporales y metadatos, evitando Data de cientos de MB retenidos en UI.

Batch con TaskGroup de ventana limitada, no crear una tarea por cada archivo esperando un semáforo. Propuesta inicial: máximo dos imágenes activas y una preview; validar con memoria real. El límite baja para imágenes grandes/presión de memoria. Presupuesto de memoria estimado incluye superficies decodificadas, resize y encoder; si un archivo supera presupuesto, rechazar con explicación antes de reservar memoria excesiva. Fase 0 fija límites numéricos de píxeles/bytes y ensayo de estrés.

## Modelos mínimos

| Tipo | Datos |
|---|---|
| ImageAsset | ID, URL autorizada, identidad/revisión, formato detectado, bytes, dimensiones, orientación, perfil, alpha, número de frames, elegibilidad |
| CompressionRequest | targetBytes Int64, outputMode, metadataPolicy, removeGPS, allowResize, limites/version de estrategia |
| CompressionCandidate | URL temporal, tipo real, dimensiones, bytes, quality opcional, metadata conservada y warnings |
| CompressionResult | assetID, estado, targetMet, candidato/salida opcional, savingsBytes, error/warnings, parámetros efectivos |
| BatchProgress | total, resueltos, activos, éxitos, fuera de objetivo, errores, cancelados, ahorro de salidas publicadas |
| RunManifest | runID, snapshot de ajustes, identidad fuente, destino reservado, backup, estado transaccional por archivo |

Los bytes son Int64. El resultado conserva hechos medidos; la UI aplica formato/idioma. Los manifests son locales; no registrar fotos, GPS ni rutas privadas en logs distribuidos.

## Acceso a archivos

Selector del sistema con acceso user-selected; equilibrar inicio/fin de acceso security-scoped cuando aplique. Bookmarks persistentes solo si realmente se añade recuperación entre sesiones; no pedir acceso completo al disco. Si la ubicación de salida requiere otro permiso, mostrar selector de destino. El acceso revocado genera error recuperable sin tocar originales.

Escaneo no recursivo de beta, sin seguir symlinks. Revalidar identidad/tamaño/fecha y, antes de reemplazo, hash fuente para detectar cambios. Comprobar destino canónico dentro de carpeta autorizada; rechazar escapes, symlinks de destino y hard links en modo reemplazo. Nombres se reservan teniendo en cuenta colisiones case-insensitive y normalización Unicode del volumen.

## Salida segura predeterminada

1. Crear subcarpeta Comprimidas. Si existe, crear Comprimidas-2, etc., reservando de forma exclusiva; nunca reutilizar a ciegas.
2. Reservar nombre por archivo de forma exclusiva; al converger foto.jpg y foto.png a JPEG, asignar sufijo estable sin sobrescribir.
3. Codificar temporal en mismo volumen que destino y con nombre propio de ejecución.
4. Finalizar, cerrar y verificar tamaño, decodificación, formato, dimensiones, alpha y política de metadata. Verificar espacio y errores reales de escritura.
5. Publicar mediante operación atómica que no sustituya un archivo existente. Si aparece una colisión entre reserva y publicación, resolver nuevo nombre o fallar; nunca sobrescribir.
6. Contabilizar éxito únicamente tras publicación. Limpiar temporales de la ejecución, no archivos ajenos.

Si no mejora el original en conservar/auto, copiar original cuando política lo permita e indicar «Sin cambios»; las reglas de metadata pueden impedir reutilizar bytes y requieren transformación verificada. Fallos dejan el original intacto.

## Reemplazo avanzado

Propuesta conservadora para beta: habilitado únicamente en «Mantener original», sobre archivos regulares sin enlaces y misma extensión/familia. Cambiar formato requiere salida separada, evitando dejar extensiones falsas o borrar fuentes con otro nombre.

1. Confirmación de UI con alcance y ubicación de respaldo.
2. Crear .comprime-backups/<runID>/ con ruta original y manifest; no sobrescribir backups previos.
3. Copiar fuente y verificar hash/tamaño del respaldo contra fuente; un hard link no cuenta como backup independiente.
4. Generar y validar temporal en volumen de fuente. Revalidar hash fuente antes de reemplazo.
5. Registrar estado previo, reemplazar atómicamente y actualizar manifest. Si falla backup, validación o identidad, no reemplazar.
6. Conservar backup indefinidamente hasta decisión explícita del usuario. Documentar restauración manual con app cerrada: consultar manifest, copiar backup a ubicación nueva, verificarlo y solo luego decidir reemplazar.

No reemplazar con candidato más grande, fuera de objetivo o degradado innecesariamente; mantener original e informar incidencia. La atomicidad es por archivo, no por lote. Después de crash reconciliar manifest, originales, temporales y backups antes de ofrecer continuación; no reanudar escrituras automáticamente sobre fuentes ambiguas.

## Cancelación y errores

Dejar de programar trabajo nuevo, cancelar tareas cooperativamente entre etapas y esperar codificadores no interrumpibles. Antes de publicar verificar cancelación. Una publicación ya iniciada termina de forma segura; outputs ya confirmados permanecen. Limpiar temporales propios y mostrar resumen parcial. Nunca intentar rollback destructivo del lote para simular «todo o nada».

Disco lleno, permiso revocado, corrupción o desconexión de volumen se registran por archivo. Ante fallo global del destino, pausar/finalizar lote con explicación, evitando repetir decenas de errores idénticos. Los resultados previos permanecen accesibles.

## Landing y entrega

Crear proyecto Next.js con TypeScript estricto y Tailwind en fase 6; fijar versiones compatibles y lockfile entonces. App Router propuesto, páginas estáticas y assets locales. Sin API de uploads ni base de datos. Recursos de terceros solo si necesarios y explícitos; preferir fuentes del sistema.

GitHub CI: app compila/testea en runner macOS Apple Silicon compatible; landing instala desde lockfile, verifica tipos/lint y build. Comandos exactos se fijan tras crear proyectos, no fingir que existen hoy.

Vercel: importar repo GitHub, Root Directory apps/landing, configuración de Next.js y runtime según versiones fijadas, previews por PR y producción desde rama acordada. Sin secretos para landing estática. Probar enlaces de descarga reales antes de publicar.

Distribución nativa separada de Vercel: build Release, firma Developer ID, notarización/stapling y artefacto verificable, según cuenta disponible. Falta de firma no bloquea desarrollo pero sí anunciar una descarga pública lista. Publicar binario en GitHub Releases cuando exista repositorio/release; landing enlaza ese artefacto.
