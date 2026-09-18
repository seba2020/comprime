import SwiftUI
import AppKit
import ImageIO
import ComprimeCore

private let accent = Color(red: 15/255, green: 118/255, blue: 110/255)
private let canvas = Color(nsColor: .windowBackgroundColor)
private let ink = Color.primary
private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }

@main
struct ComprimeApp: App {
    var body: some Scene {
        WindowGroup("Comprime") {
            MainView()
                .frame(minWidth: 1100, minHeight: 720)
        }
            .defaultSize(width: 1360, height: 860)
    }
}

private struct PreviewImages: @unchecked Sendable {
    let original: CGImage
    let compressed: CGImage
}
private func loadImages(original: URL, compressed: URL, edge: Int) throws -> PreviewImages {
    func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { throw CompressionError.encodeFailed }
        return image
    }
    return try PreviewImages(original: load(original), compressed: load(compressed))
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var snapshot = ScanSnapshot()
    @Published var folder: URL?
    @Published var selected: URL?
    @Published var scanning = false
    @Published var message: String?
    @Published var preset = 1_000_000
    @Published var custom = "1"
    @Published var customUnit = 1_000_000
    @Published var mode = "preserve"
    @Published var outputFormat = ImageFormat.webp
    @Published var allowResize = true
    @Published var keepMetadata = true
    @Published var removeGPS = false
    @Published var replaceOriginals = false
    @Published var preview: CompressionCandidate?
    @Published fileprivate var images: PreviewImages?
    @Published var previewing = false
    @Published var previewError: String?
    @Published var batch = BatchSnapshot()
    @Published var running = false
    @Published var cancelling = false
    @Published var zoom = 0.0
    private var scopedFolder: URL?
    private var scanTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?
    private var generation = UUID()
    private var previewGeneration = UUID()
    private var imageGeneration = UUID()
    private var batchControl = BatchControl()

    var selectedAsset: ImageAsset? { snapshot.assets.first { $0.id == selected } }
    var settingsKey: String { "\(preset)|\(custom)|\(customUnit)|\(mode)|\(outputFormat)|\(allowResize)|\(keepMetadata)|\(removeGPS)" }
    var target: Int64? {
        if preset > 0 { return Int64(preset) }
        guard let amount = Double(custom.replacingOccurrences(of: ",", with: ".")), amount.isFinite,
              amount > 0, amount * Double(customUnit) >= 1, amount * Double(customUnit) < Double(Int64.max) else { return nil }
        return Int64(amount * Double(customUnit))
    }
    func request() throws -> CompressionRequest {
        guard let target else { throw CompressionError.invalidTarget }
        let output: OutputMode = mode == "auto" ? .automatic : (mode == "convert" ? .convert(outputFormat) : .preserve)
        return try CompressionRequest(targetBytes: target, outputMode: output,
            metadataPolicy: keepMetadata ? .preserve : .remove, removeGPS: removeGPS, allowResize: allowResize)
    }
    func openFolder() {
        guard !running else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Abrir carpeta"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanTask?.cancel(); resetPreview()
        if let scopedFolder { scopedFolder.stopAccessingSecurityScopedResource() }
        scopedFolder = url.startAccessingSecurityScopedResource() ? url : nil
        generation = UUID()
        let current = generation
        snapshot = ScanSnapshot(); folder = url; selected = nil; scanning = true; message = nil
        batch = BatchSnapshot()
        scanTask = Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                for try await update in FolderScanner().scan(url) {
                    guard current == generation, !Task.isCancelled else { return }
                    snapshot = update
                    if selected == nil, let first = update.assets.first?.id {
                        selected = first
                        // Let the user inspect and tune the first photo while the rest
                        // of a large folder is still being catalogued.
                        refreshPreview()
                    }
                }
                guard current == generation else { return }
                scanning = false
                if snapshot.assets.isEmpty { message = "No encontramos imágenes compatibles en esta carpeta." }
                refreshPreview()
            } catch {
                guard current == generation else { return }
                scanning = false; message = friendly(error)
            }
        }
    }
    func cancelScan() {
        scanTask?.cancel(); scanning = false
        message = "Análisis cancelado. Se muestran los archivos encontrados."
        refreshPreview()
    }
    func resetPreview() {
        previewGeneration = UUID(); imageGeneration = UUID()
        previewTask?.cancel(); imageTask?.cancel()
        if let preview { discard(preview) }
        preview = nil; images = nil; previewError = nil; previewing = false
    }
    func refreshPreview() {
        guard !running else { return }
        resetPreview()
        guard let asset = selectedAsset, let folder else { return }
        let request: CompressionRequest
        do { request = try self.request() } catch { previewError = friendly(error); return }
        let current = previewGeneration
        previewing = true
        previewTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                let worker = Task.detached(priority: .userInitiated) {
                    let access = folder.startAccessingSecurityScopedResource()
                    defer { if access { folder.stopAccessingSecurityScopedResource() } }
                    return try await LocalCompressionEngine().compress(asset, request: request)
                }
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard current == previewGeneration, !Task.isCancelled else { discard(result); return }
                preview = result; previewing = false
                refreshImages()
            } catch {
                guard current == previewGeneration, !Task.isCancelled else { return }
                previewing = false; previewError = friendly(error)
            }
        }
    }
    func refreshImages() {
        imageTask?.cancel(); imageGeneration = UUID()
        guard let asset = selectedAsset, let preview, let folder else { return }
        let current = imageGeneration
        let edge = zoom == 0 ? 1800 : max(asset.width, asset.height)
        imageTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let access = folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                return try loadImages(original: asset.url, compressed: preview.temporaryURL, edge: edge)
            }
            do {
                let result = try await worker.value
                guard current == imageGeneration, !Task.isCancelled else { return }
                images = result
            } catch { if current == imageGeneration { previewError = friendly(error) } }
        }
    }
    var samples: [ImageAsset] {
        let sorted = snapshot.assets.sorted { a, b in
            let ac = Double(a.bytes) / Double(max(1, a.width * a.height))
            let bc = Double(b.bytes) / Double(max(1, b.width * b.height))
            return ac == bc ? a.url.path < b.url.path : ac < bc
        }
        guard sorted.count > 3 else { return sorted }
        return [sorted[0], sorted[sorted.count / 2], sorted[sorted.count - 1]]
    }
    func startBatch() {
        guard !running, !scanning, let folder, !snapshot.assets.isEmpty else { return }
        let request: CompressionRequest
        do { request = try self.request() } catch { message = friendly(error); return }
        let assets = snapshot.assets
        resetPreview()
        running = true; cancelling = false; message = nil; batch = BatchSnapshot(); batch.total = assets.count
        batchControl = BatchControl()
        let control = batchControl, replace = replaceOriginals && mode == "preserve"
        batchTask = Task {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            do {
                for try await update in BatchProcessor().run(folder: folder, assets: assets, request: request, replaceOriginals: replace, control: control) {
                    batch = update
                }
                running = false; cancelling = false
                if replace { message = "Los originales procesados cambiaron. Vuelve a abrir la carpeta antes de comprimir otra vez." }
                else { refreshPreview() }
            } catch { running = false; cancelling = false; message = friendly(error) }
        }
    }
    func cancelBatch() { cancelling = true; batchControl.cancel() }
    func revealOutput() { if let output = batch.outputFolder { NSWorkspace.shared.open(output) } }
}

struct MainView: View {
    @StateObject private var model = LibraryModel()
    @State private var showIssues = false
    @State private var confirmReplace = false
    @AppStorage("appearance") private var appearance = "system"
    private var preferredScheme: ColorScheme? { appearance == "dark" ? .dark : (appearance == "light" ? .light : nil) }
    var body: some View {
        VStack(spacing: 0) {
            appHeader
            Divider()
            NavigationSplitView(sidebar: {
                VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button("Abrir carpeta", systemImage: "folder", action: model.openFolder)
                    .keyboardShortcut("o", modifiers: .command).disabled(model.running)
                if let folder = model.folder {
                    Divider()
                    Text(folder.lastPathComponent).font(.headline).lineLimit(1)
                    Text("\(model.snapshot.assets.count) imágenes · \(bytes(model.snapshot.totalBytes))").font(.subheadline)
                    if !model.snapshot.assets.isEmpty { Text("\(bytes(model.snapshot.totalBytes / Int64(model.snapshot.assets.count))) promedio").font(.caption).foregroundStyle(.secondary) }
                    Text("No incluye subcarpetas").font(.caption2).foregroundStyle(.secondary)
                    Text(formatSummary).font(.caption).foregroundStyle(.secondary)
                }
                if model.scanning { ProgressView("Analizando…"); Button("Cancelar", action: model.cancelScan) }
                if !model.snapshot.issues.isEmpty { Button("\(model.snapshot.issues.count) incidencias") { showIssues = true } }
            }.padding(18)
            List(model.snapshot.assets, selection: $model.selected) { asset in
                HStack(spacing: 10) {
                    thumbnail(asset, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.url.lastPathComponent).lineLimit(1).help(asset.url.lastPathComponent)
                        Text("\(asset.format.rawValue) · \(bytes(asset.bytes))").font(.caption).foregroundStyle(.secondary)
                    }
                }.tag(asset.id)
            }.disabled(model.running)
            Text("Tus fotos no salen de tu Mac.").font(.caption).foregroundStyle(.secondary).padding(14)
                }
        }, detail: {
            HStack(spacing: 0) {
                VStack(spacing: 18) {
                    if let asset = model.selectedAsset {
                        HStack { Text(asset.url.lastPathComponent).font(.headline).lineLimit(1); Spacer(); Text("Vista previa").foregroundStyle(.secondary) }
                        comparison(asset)
                        samples
                        if let preview = model.preview { previewMetrics(asset, preview) }
                        if model.running || model.batch.finished { batchPanel }
                    } else { welcome }
                    if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector.frame(width: 280).padding(20)
            }
            .background(canvas)
            })
        }
        .background(canvas)
        .tint(accent)
        .preferredColorScheme(preferredScheme)
        .onChange(of: model.selected) { _, _ in model.zoom = 0; model.refreshPreview() }
        .onChange(of: model.settingsKey) { _, _ in if model.mode != "preserve" { model.replaceOriginals = false }; model.refreshPreview() }
        .onChange(of: model.zoom) { old, new in if (old == 0) != (new == 0) { model.refreshImages() } }
        .confirmationDialog("Reemplazar originales después de crear respaldo", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Crear respaldos y comprimir", role: .destructive, action: model.startBatch)
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Se guardará una copia verificada en .comprime-backups antes de reemplazar cada original. Los archivos que no mejoren o no cumplan el objetivo se conservarán.") }
        .sheet(isPresented: $showIssues) { issues }
    }
    private var appHeader: some View {
        HStack(spacing: 12) {
            CompressionMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Comprime").font(.title3.weight(.semibold)).foregroundStyle(ink)
                Text("Mismas fotos. Menos peso.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir carpeta", systemImage: "folder", action: model.openFolder)
                .disabled(model.running)
            Button("Ayuda", systemImage: "questionmark.circle") { model.message = "Elige una carpeta, define el peso por imagen y revisa la comparación antes de comprimir." }
            Picker("Apariencia", selection: $appearance) {
                Text("Sistema").tag("system")
                Text("Claro").tag("light")
                Text("Oscuro").tag("dark")
            }
            .labelsHidden()
            .frame(width: 92)
            Label("100% local", systemImage: "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(accent)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    private var formatSummary: String {
        ImageFormat.allCases.compactMap { f in let n = model.snapshot.assets.filter { $0.format == f }.count; return n > 0 ? "\(f.rawValue) \(n)" : nil }.joined(separator: " · ")
    }
    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            CompressionMark(size: 72)
            Text("Mismas fotos.\nMenos peso.").font(.system(size: 36, weight: .semibold)).multilineTextAlignment(.center)
            Text("Elige una carpeta. Dile cuánto deben pesar.").foregroundStyle(.secondary)
            Button("Abrir carpeta", action: model.openFolder).buttonStyle(.borderedProminent).controlSize(.large)
            Text("JPG · JPEG · PNG · HEIC · HEIF · WebP").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private func comparison(_ asset: ImageAsset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
            if let images = model.images {
                ComparisonView(original: images.original, compressed: images.compressed, sourceWidth: (5...8).contains(asset.orientation) ? asset.height : asset.width,
                    sourceHeight: (5...8).contains(asset.orientation) ? asset.width : asset.height, zoom: $model.zoom)
            } else if model.previewing {
                VStack(spacing: 14) { ProgressView(); Text("Buscando la mejor calidad…").foregroundStyle(.secondary); Text("El peso mostrado será el del archivo real.").font(.caption).foregroundStyle(.secondary) }
            } else if let error = model.previewError {
                VStack(spacing: 12) { Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange); Text(error).multilineTextAlignment(.center); Button("Reintentar", action: model.refreshPreview) }.padding(30)
            } else if model.running { VStack { ProgressView(); Text("Comprimiendo carpeta…").padding(.top, 8) } }
            else { ProgressView("Preparando comparación…") }
        }
        .frame(minHeight: 210, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
    private var samples: some View {
        HStack(spacing: 10) {
            Text("Muestras").font(.caption).foregroundStyle(.secondary)
            ForEach(model.samples) { asset in
                Button { model.selected = asset.id } label: {
                    thumbnail(asset, size: 42).padding(3).background(model.selected == asset.id ? accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).help(asset.url.lastPathComponent).disabled(model.running)
            }
            Spacer()
            Picker("Zoom", selection: $model.zoom) { Text("Fit").tag(0.0); Text("50%").tag(0.5); Text("100%").tag(1.0); Text("200%").tag(2.0) }.frame(width: 130).disabled(model.images == nil)
        }
    }
    private func previewMetrics(_ asset: ImageAsset, _ preview: CompressionCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bytes(asset.bytes)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(bytes(preview.bytes)).font(.title2.weight(.semibold)).foregroundStyle(accent)
                Spacer()
                Text(String(format: "%+.0f%%", -100 * (1 - Double(preview.bytes) / Double(max(1, asset.bytes))))).font(.title3.weight(.medium)).foregroundStyle(accent)
            }
            HStack { Text("\(asset.format.rawValue) → \(preview.format.rawValue) · \(preview.width) × \(preview.height)"); Spacer(); if let q = preview.quality { Text("Calidad \(Int((q * 100).rounded()))") } }
                .font(.caption).foregroundStyle(.secondary)
            if let target = model.target, preview.bytes > target { Label("No alcanza el objetivo con estos límites", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            ForEach(preview.warnings.filter { $0.hasPrefix("Resolución") }, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            if !preview.warnings.isEmpty {
                DisclosureGroup("Detalles del resultado") { ForEach(preview.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) } }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Comprime a tu medida").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text("Objetivo por imagen").font(.headline)
                Picker("Objetivo por imagen", selection: $model.preset) {
                    Text("500 KB").tag(500_000); Text("1 MB").tag(1_000_000); Text("2 MB").tag(2_000_000); Text("5 MB").tag(5_000_000); Text("Personalizado").tag(0)
                }.labelsHidden()
                if model.preset == 0 {
                    HStack { TextField("Cantidad", text: $model.custom).textFieldStyle(.roundedBorder); Picker("Unidad", selection: $model.customUnit) { Text("KB").tag(1000); Text("MB").tag(1_000_000) }.labelsHidden().frame(width: 80) }
                }
                if model.target == nil { Text("Introduce un peso válido mayor que cero.").font(.caption).foregroundStyle(.red) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Formato de salida").font(.headline)
                Picker("Formato de salida", selection: $model.mode) { Text("Mantener original").tag("preserve"); Text("Optimizar automáticamente").tag("auto"); Text("Convertir todas a…").tag("convert") }.labelsHidden()
                if model.mode == "convert" { Picker("Convertir a", selection: $model.outputFormat) { ForEach([ImageFormat.jpeg, .png, .heic, .webp], id: \.self) { Text($0.rawValue).tag($0) } } }
            }
            Divider()
            DisclosureGroup("Opciones avanzadas") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Permitir reducir resolución", isOn: $model.allowResize)
                    Toggle("Mantener metadata compatible", isOn: $model.keepMetadata)
                    Toggle("Eliminar ubicación GPS", isOn: $model.removeGPS)
                    Toggle("Reemplazar con respaldo", isOn: $model.replaceOriginals).disabled(model.mode != "preserve")
                    Text("Metadata no representable puede omitirse. Los formatos con transparencia se conservan sin aplanar.").font(.caption2).foregroundStyle(.secondary)
                }.font(.callout).padding(.top, 10)
            }
            Spacer()
            Label(model.replaceOriginals ? "Respaldo verificado antes de reemplazar." : "Se guardan en Comprimidas. Tus originales se conservan.", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
            Button {
                if model.replaceOriginals { confirmReplace = true } else { model.startBatch() }
            } label: { Text("Comprimir \(model.snapshot.assets.count) fotos").frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.snapshot.assets.isEmpty || model.scanning || model.running || model.target == nil)
            Text("100% local · Sin cuentas").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07)))
        .disabled(model.running)
    }
    private var batchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.running ? (model.cancelling ? "Cancelando de forma segura…" : "Comprimiendo…") : (model.batch.cancelled ? "Compresión cancelada" : "Compresión terminada")).font(.headline)
                Spacer()
                Text("\(model.batch.items.count) / \(model.batch.total)").monospacedDigit()
            }
            ProgressView(value: Double(model.batch.items.count), total: Double(max(1, model.batch.total)))
            HStack {
                Text("\(bytes(model.batch.before)) → \(bytes(model.batch.after)) · Ahorro \(bytes(model.batch.before - model.batch.after))").font(.caption)
                Spacer()
                if model.running { Button("Cancelar", action: model.cancelBatch).disabled(model.cancelling) }
                else { Button("Abrir salida", action: model.revealOutput) }
            }
            if let last = model.batch.items.last { Text("\(last.source.lastPathComponent) · \(last.message)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            if !model.running {
                HStack { Text("\(model.batch.items.filter { $0.targetMet }.count) cumplen el objetivo").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Ver resultados") { showIssues = true } }
            }
        }.padding(16).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private var issues: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resultados e incidencias").font(.title2)
            List {
                ForEach(model.snapshot.issues) { issue in VStack(alignment: .leading) { Text(issue.url.lastPathComponent).font(.headline); Text(issue.reason).foregroundStyle(.secondary) } }
                ForEach(model.batch.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.source.lastPathComponent).font(.headline)
                        Text(item.message).foregroundStyle(item.output == nil ? .orange : .secondary)
                        if item.output != nil { Text("\(bytes(item.originalBytes)) → \(bytes(item.outputBytes))").font(.caption) }
                        ForEach(item.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if let backup = model.batch.backupFolder { Button("Abrir respaldos") { NSWorkspace.shared.open(backup) } }
            Button("Cerrar") { showIssues = false }.keyboardShortcut(.defaultAction)
        }.padding(24).frame(width: 680, height: 500)
    }
    private func thumbnail(_ asset: ImageAsset, size: CGFloat) -> some View {
        Group { if let data = asset.thumbnail, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct CompressionMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 26/255, green: 34/255, blue: 36/255), Color(red: 12/255, green: 18/255, blue: 20/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, canvasSize in
                let s = min(canvasSize.width, canvasSize.height)
                var left = Path()
                left.move(to: CGPoint(x: s * 0.20, y: s * 0.30))
                left.addLine(to: CGPoint(x: s * 0.42, y: s * 0.50))
                left.addLine(to: CGPoint(x: s * 0.20, y: s * 0.70))
                var right = Path()
                right.move(to: CGPoint(x: s * 0.80, y: s * 0.30))
                right.addLine(to: CGPoint(x: s * 0.58, y: s * 0.50))
                right.addLine(to: CGPoint(x: s * 0.80, y: s * 0.70))
                context.stroke(left, with: .color(Color(red: 114/255, green: 225/255, blue: 190/255)), style: StrokeStyle(lineWidth: s * 0.105, lineCap: .round, lineJoin: .round))
                context.stroke(right, with: .color(Color(red: 114/255, green: 225/255, blue: 190/255)), style: StrokeStyle(lineWidth: s * 0.105, lineCap: .round, lineJoin: .round))
                context.fill(Path(roundedRect: CGRect(x: s * 0.43, y: s * 0.40, width: s * 0.14, height: s * 0.20), cornerRadius: s * 0.035), with: .color(.white.opacity(0.92)))
            }
            .padding(size * 0.08)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.04)
        .accessibilityLabel("Icono de Comprime")
    }
}

private struct ComparisonView: View {
    let original: CGImage
    let compressed: CGImage
    let sourceWidth: Int
    let sourceHeight: Int
    @Binding var zoom: Double
    @State private var fraction = 0.5
    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / CGFloat(sourceWidth), geo.size.height / CGFloat(sourceHeight))
            let scale = zoom == 0 ? fit : CGFloat(zoom) / (NSScreen.main?.backingScaleFactor ?? 2)
            let width = CGFloat(sourceWidth) * scale, height = CGFloat(sourceHeight) * scale
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .leading) {
                    checkerboard
                    Image(decorative: original, scale: 1).resizable().interpolation(.high).frame(width: width, height: height)
                    Image(decorative: compressed, scale: 1).resizable().interpolation(.high).frame(width: width, height: height)
                        .mask(HStack(spacing: 0) { Color.clear.frame(width: width * fraction); Color.black })
                    Color.clear.frame(width: 28, height: height)
                        .overlay(Rectangle().fill(.white).frame(width: 2))
                        .overlay(Image(systemName: "arrow.left.and.right").font(.caption).padding(6).background(accent, in: Circle()).foregroundStyle(.white))
                        .contentShape(Rectangle()).offset(x: width * fraction - 14)
                        .gesture(DragGesture(coordinateSpace: .named("comparison")).onChanged { fraction = min(1, max(0, $0.location.x / width)) })
                }.frame(width: width, height: height).coordinateSpace(name: "comparison").frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            VStack {
                HStack { Text("Original"); Spacer(); Text("Comprimida") }.font(.caption.weight(.medium)).padding(10).background(.regularMaterial)
                Spacer()
                Slider(value: $fraction, in: 0...1).tint(accent).padding(12).background(.regularMaterial)
                    .accessibilityLabel("División Original y Comprimida")
            }
        }
    }
    private var checkerboard: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for y in stride(from: 0.0, to: size.height, by: 16) {
                for x in stride(from: 0.0, to: size.width, by: 16) where (Int(x / 16) + Int(y / 16)) % 2 == 0 {
                    context.fill(Path(CGRect(x: x, y: y, width: 16, height: 16)), with: .color(.gray.opacity(0.16)))
                }
            }
        }
    }
}
