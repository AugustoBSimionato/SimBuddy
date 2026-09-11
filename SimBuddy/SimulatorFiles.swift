//
//  SimulatorFiles.swift
//  SimBuddy
//
//  Created by Augusto Simionato on 11/09/26.
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct SharedItem: Identifiable, Hashable, Sendable {
    enum Location: Hashable, Sendable {
        case photos
        case files

        var title: LocalizedStringResource {
            switch self {
            case .photos: "No app Fotos"
            case .files: "No app Arquivos"
            }
        }
    }

    let url: URL
    let location: Location
    let dateAdded: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isDeletable: Bool { location == .files }
}

nonisolated enum SimulatorFiles {
    struct FilesAppUnavailable: LocalizedError {
        var errorDescription: String? {
            String(localized: "O app Arquivos ainda não está disponível neste simulador.")
        }
    }

    private static let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .addedToDirectoryDateKey]

    static func isPhotoLibraryMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    @concurrent
    static func items(in dataURL: URL) async -> [SharedItem] {
        let photoFolders = contents(of: dataURL.appending(path: "Media/DCIM", directoryHint: .isDirectory)).filter(isDirectory)
        let photos = photoFolders
            .flatMap { listItems(in: $0, location: .photos) }
            .filter { isPhotoLibraryMedia($0.url) }
        let files = filesDirectory(in: dataURL).map { listItems(in: $0, location: .files) } ?? []

        return (photos + files).sorted {
            if $0.dateAdded != $1.dateAdded { return $0.dateAdded > $1.dateAdded }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @concurrent
    static func copy(_ url: URL, toFilesIn dataURL: URL) async throws {
        guard let directory = filesDirectory(in: dataURL) else { throw FilesAppUnavailable() }
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try FileManager.default.copyItem(at: url, to: availableURL(for: url.lastPathComponent, in: directory))
    }

    @concurrent
    static func remove(_ items: [SharedItem]) async throws {
        for item in items where item.isDeletable {
            try FileManager.default.removeItem(at: item.url)
        }
    }

    // "On My iPhone" in the Files app is backed by this app group's File Provider Storage folder.
    private static func filesDirectory(in dataURL: URL) -> URL? {
        let groups = dataURL.appending(path: "Containers/Shared/AppGroup", directoryHint: .isDirectory)
        let localStorage = contents(of: groups).first { group in
            let metadataURL = group.appending(path: ".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return false }
            return metadata["MCMMetadataIdentifier"] as? String == "group.com.apple.FileProvider.LocalStorage"
        }
        return localStorage?.appending(path: "File Provider Storage", directoryHint: .isDirectory)
    }

    private static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: .skipsHiddenFiles
        )) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private static func listItems(in directory: URL, location: SharedItem.Location) -> [SharedItem] {
        contents(of: directory).map { url in
            let dateAdded = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
            return SharedItem(url: url, location: location, dateAdded: dateAdded ?? .distantPast)
        }
    }

    private static func availableURL(for name: String, in directory: URL) -> URL {
        let baseName = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let numberedName = "\(baseName) \(number)"
            candidate = directory.appending(path: pathExtension.isEmpty ? numberedName : "\(numberedName).\(pathExtension)")
            number += 1
        }
        return candidate
    }
}
