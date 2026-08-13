//
//  Extensions.swift
//  AppMover
//
//  Created by Oskar Groth on 2019-12-22.
//  Copyright © 2019 Oskar Groth. All rights reserved.
//
//  Vendored from https://github.com/OskarGroth/AppMover (MIT).
//

import Cocoa
import Foundation

extension URL {

    var representsBundle: Bool {
        pathExtension == "app"
    }

    var isValid: Bool {
        !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var numberOfFilesInDirectory: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.count ?? 0
    }
}

extension Bundle {

    var localizedName: String {
        NSRunningApplication.current.localizedName ?? "The App"
    }

    var isInstalled: Bool {
        let applicationDirs = FileManager.default.urls(
            for: .applicationDirectory, in: .allDomainsMask)
        return AppInstallLocation.isInstalled(
            bundlePath: bundlePath,
            applicationDirectoryPaths: applicationDirs.map(\.path))
    }

    func copy(to url: URL) throws {
        try FileManager.default.copyItem(at: bundleURL, to: url)
    }
}

extension Process {

    static func runTask(
        command: String,
        arguments: [String] = [],
        completion: ((Int32) -> Void)? = nil
    ) {
        let task = Process()
        task.launchPath = command
        task.arguments = arguments
        task.terminationHandler = { task in
            completion?(task.terminationStatus)
        }
        task.launch()
    }
}
