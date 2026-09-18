# Corpus de pruebas

Corpus inicial generado en generated/; ver manifest.json para hashes y procedencia. Faltan variantes avanzadas y fotografías reales para cerrar fase 0. Usar imágenes propias autorizadas o fixtures sintéticos; registrar origen/licencia, hash, dimensiones, perfil, orientación, alpha, bytes y resultado esperado. No incorporar fotos personales o coordenadas GPS reales al repositorio.

Cubrir JPEG/JPG simples y detallados; PNG opaco/transparente con texto; HEIC y HEIF admitidos; WebP opaco/transparente; EXIF rotado; ICC/P3; GPS sintético; animación; HDR/auxiliares; corruptos; extensión falsa; archivo bajo objetivo; objetivo imposible; nombres Unicode/colisiones; fuente cambiada; imagen que excede límites de memoria. Probar errores de escritura mediante inyección en directorio temporal, nunca sobre originales del usuario.

Guardar expectativas separadas de salidas. Comparar bytes cuando se espera copia intacta y propiedades/píxeles cuando hay transformación. Los bytes de un codec pueden variar por sistema; no exigir golden binario entre versiones salvo contrato explícito. Ejecutar pruebas de reemplazo solo sobre copias desechables.
