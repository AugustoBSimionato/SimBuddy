//
//  SharingSection.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import QuickLook
import QuickLookThumbnailing
import SwiftUI

struct SharingSection: View {
    @Environment(SimulatorViewModel.self) private var store

    var body: some View {
        Section {
            if let simulator = store.selectedSimulator {
                if simulator.supportsFileSharing {
                    SharedFilesTray(simulator: simulator)
                        .id(simulator.id)
                } else {
                    Text("O compartilhamento de arquivos não está disponível para simuladores de \(simulator.runtime.platform).")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Selecione um simulador na barra lateral para enviar arquivos para ele.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Compartilhamento")
        } footer: {
            Text("Solte arquivos na bandeja para enviá-los ao simulador: imagens e vídeos vão para o app Fotos; o resto, para o app Arquivos. Itens do Fotos só podem ser excluídos no próprio simulador.")
        }
    }
}

private struct SharedFilesTray: View {
    @Environment(SimulatorViewModel.self) private var store
    let simulator: Simulator

    @State private var items: [SharedItem] = []
    @State private var selection: Set<SharedItem.ID> = []
    @State private var isTargeted = false
    @State private var previewedURL: URL?
    @State private var pendingDeletion: [SharedItem]?
    @FocusState private var isFocused: Bool

    private var selectedItems: [SharedItem] { items.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tray
            actionBar
        }
        .task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onChange(of: store.sharedFilesRevision) {
            Task { await reload() }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { items in
            Button("Excluir", role: .destructive) {
                selection.subtract(items.map(\.id))
                Task { await store.deleteSharedItems(items) }
            }
        } message: { _ in
            Text("Esta ação não pode ser desfeita.")
        }
    }

    private var tray: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(items) { item in
                        SharedItemTile(item: item, isSelected: selection.contains(item.id), isFocused: isFocused)
                            .onTapGesture { click(item) }
                            .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(8)
            }
            .frame(height: 132)
            .overlay {
                if items.isEmpty { emptyState }
            }
            .background { trayBackground }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
            .onTapGesture {
                selection = []
                isFocused = true
            }
            .focusable(interactions: .edit)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                moveSelection(by: press.key == .leftArrow ? -1 : 1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.space) {
                previewedURL = previewedURL == nil ? (selectedItems.first ?? items.first)?.url : nil
                return .handled
            }
            .onDeleteCommand { requestDeletion(of: selectedItems) }
        }
        .dropDestination(for: URL.self, isEnabled: store.canShare(with: simulator)) { urls, _ in
            let fileURLs = urls.filter(\.isFileURL)
            Task { await store.share(fileURLs, with: simulator) }
        }
        .onDropSessionUpdated { session in
            isTargeted = session.phase == .entering || session.phase == .active
        }
        .quickLookPreview($previewedURL, in: items.map(\.url))
        .animation(.default, value: isTargeted)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.title2)
            Text("Arraste arquivos para cá")
        }
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
    }

    private var trayBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.quinary))
            .overlay {
                if isTargeted {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2)
                } else if items.isEmpty {
                    shape.strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Enviar arquivos…", systemImage: "plus") {
                store.isImportingFiles = true
            }
            .help("Escolher arquivos para enviar ao simulador")
            .disabled(!store.canShare(with: simulator))

            Button("Excluir", systemImage: "minus") {
                requestDeletion(of: selectedItems)
            }
            .help("Excluir do simulador os itens selecionados")
            .disabled(!selectedItems.contains(where: \.isDeletable))

            Spacer()

            Group {
                if store.simulatorsReceivingFiles.contains(simulator.id) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Enviando…")
                } else if !simulator.isBooted {
                    Text("Inicie o simulador para enviar arquivos.")
                }
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

    @ViewBuilder
    private func contextMenu(for item: SharedItem) -> some View {
        let targets = selection.contains(item.id) ? selectedItems : [item]

        Button("Visualização Rápida", systemImage: "eye") {
            previewedURL = item.url
        }
        Button("Mostrar no Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
        }
        Divider()
        Button("Excluir do simulador", systemImage: "trash", role: .destructive) {
            requestDeletion(of: targets)
        }
        .disabled(!targets.contains(where: \.isDeletable))
    }

    private var deletionTitle: String {
        guard let items = pendingDeletion else { return "" }
        return items.count == 1
            ? String(localized: "Excluir “\(items[0].name)” do simulador?")
            : String(localized: "Excluir \(items.count) itens do simulador?")
    }

    private func click(_ item: SharedItem) {
        isFocused = true
        if !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) {
            selection.formSymmetricDifference([item.id])
        } else {
            selection = [item.id]
            if NSApp.currentEvent?.clickCount == 2 { previewedURL = item.url }
        }
    }

    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let current = offset < 0
            ? items.firstIndex { selection.contains($0.id) }
            : items.lastIndex { selection.contains($0.id) }
        let index = current.map { min(max($0 + offset, 0), items.count - 1) } ?? 0
        selection = [items[index].id]
        proxy.scrollTo(items[index].id)
    }

    private func requestDeletion(of items: [SharedItem]) {
        let deletable = items.filter(\.isDeletable)
        if deletable.isEmpty {
            NSSound.beep()
        } else {
            pendingDeletion = deletable
        }
    }

    private func reload() async {
        guard let dataURL = simulator.dataURL else { return }
        let items = await SimulatorFiles.items(in: dataURL)
        if items != self.items { self.items = items }
        let validSelection = selection.intersection(items.map(\.id))
        if validSelection != selection { selection = validSelection }
    }
}

private struct SharedItemTile: View {
    let item: SharedItem
    let isSelected: Bool
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            SharedItemThumbnail(url: item.url)
                .frame(width: 64, height: 64)
                .padding(4)
                .background(.quaternary.opacity(isSelected ? 1 : 0), in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: item.location == .photos ? "photo" : "folder")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(.regularMaterial, in: .circle)
                }

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected && isFocused ? Color.white : Color.primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(nameBackground, in: .rect(cornerRadius: 4, style: .continuous))
        }
        .frame(width: 96)
        .contentShape(.rect)
        .help(Text(verbatim: item.name))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(item.location.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var nameBackground: AnyShapeStyle {
        guard isSelected else { return AnyShapeStyle(.clear) }
        return isFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)
    }
}

private struct SharedItemThumbnail: View {
    let url: URL
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: NSImage?

    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
            .resizable()
            .scaledToFit()
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: CGSize(width: 64, height: 64),
                    scale: displayScale,
                    representationTypes: .thumbnail
                )
                thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            }
    }
}
