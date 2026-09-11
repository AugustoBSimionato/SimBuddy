//
//  ContentView.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 16/08/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SimulatorStore.self) private var store
    @State private var searchText = ""
    @SceneStorage("showsRunningOnly") private var showsRunningOnly = false
    @FocusState private var isSidebarFocused: Bool

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SimulatorSidebar(searchText: searchText, showsRunningOnly: $showsRunningOnly)
                .focused($isSidebarFocused)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
                .toolbar {
                    ToolbarItemGroup {
                        Toggle("Mostrar só em execução", systemImage: "line.3.horizontal.decrease", isOn: $showsRunningOnly)
                            .help("Mostrar só os simuladores em execução")

                        Button("Atualizar", systemImage: "arrow.clockwise") {
                            Task { await store.refresh() }
                        }
                        .help("Atualizar a lista de simuladores")
                    }
                }
        } detail: {
            OverridesForm()
        }
        .onAppear { isSidebarFocused = true }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text("Buscar"))
        .navigationSubtitle(subtitle)
        .frame(minWidth: 780, minHeight: 540)
        .task { await store.monitor() }
        .alert(
            store.failure?.title ?? "",
            isPresented: Binding(
                get: { store.failure != nil },
                set: { if !$0 { store.failure = nil } }
            ),
            presenting: store.failure
        ) { _ in
            Button("OK") {}
        } message: { failure in
            Text(failure.message)
        }
        .fileImporter(isPresented: $store.isImportingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, let simulator = store.selectedSimulator else { return }
            Task { await store.share(urls, with: simulator) }
        }
    }

    private var subtitle: String {
        if let confirmation = store.confirmation { return confirmation }
        guard store.hasLoaded else { return "" }
        let count = store.bootedSimulators.count
        return count == 0
            ? String(localized: "Nenhum simulador em execução")
            : String(localized: "\(count) em execução")
    }
}
