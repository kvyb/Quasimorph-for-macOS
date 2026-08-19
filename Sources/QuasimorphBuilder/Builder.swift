import CryptoKit
import Darwin
import Foundation

public enum BuilderFailure: LocalizedError, Equatable {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}

public struct LockedDependency: Equatable, Sendable {
    public let name: String
    public let fileName: String
    public let version: String
    public let url: URL
    public let sha256: String

    public init(name: String, fileName: String, version: String, url: URL, sha256: String) {
        self.name = name
        self.fileName = fileName
        self.version = version
        self.url = url
        self.sha256 = sha256
    }
}

public enum LockedDependencies {
    public static let template = LockedDependency(
        name: "Sikarugir wrapper template",
        fileName: "Template-1.0.11.tar.xz",
        version: "1.0.11",
        url: URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz")!,
        sha256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a"
    )

    public static let engine = LockedDependency(
        name: "Whisky Wine runtime",
        fileName: "Whisky-Libraries-v4.5.105-beta.1.tar.gz",
        version: "Wine 11.15 / Whisky 4.5.105-beta.1",
        url: URL(string: "https://github.com/frankea/Whisky/releases/download/v4.5.105-beta.1/Libraries.tar.gz")!,
        sha256: "43d78bec577166b5f64b1903f92582e673fbb142ad23921550f77cfeb9ffe0ce"
    )

    public static let sevenZip = LockedDependency(
        name: "7-Zip archive helper",
        fileName: "7z2602-mac.tar.xz",
        version: "26.02",
        url: URL(string: "https://github.com/ip7z/7zip/releases/download/26.02/7z2602-mac.tar.xz")!,
        sha256: "1cf6760579502f87e591ff5c73a005ec50b3e4d6f507e8b038382d563c3175b9"
    )

    public static let steamInstaller = LockedDependency(
        name: "Valve Steam installer",
        fileName: "SteamSetup.exe",
        version: "2026-08-05",
        url: URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!,
        sha256: "7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb"
    )

    public static let all = [template, engine, sevenZip, steamInstaller]
}

public enum BuildSource: Equatable, Sendable {
    case gameFiles(URL)
    case steam
}

public struct BuildOptions: Sendable {
    public var source: BuildSource
    public var outputDirectory: URL
    public var cacheDirectory: URL
    public var dependencyDirectory: URL?
    public var createDMG: Bool
    public var keepWorkDirectory: Bool
    public var force: Bool
    public var offline: Bool
    public var verbose: Bool

    public init(
        source: BuildSource,
        outputDirectory: URL,
        cacheDirectory: URL,
        dependencyDirectory: URL? = nil,
        createDMG: Bool = true,
        keepWorkDirectory: Bool = false,
        force: Bool = false,
        offline: Bool = false,
        verbose: Bool = false
    ) {
        self.source = source
        self.outputDirectory = outputDirectory
        self.cacheDirectory = cacheDirectory
        self.dependencyDirectory = dependencyDirectory
        self.createDMG = createDMG
        self.keepWorkDirectory = keepWorkDirectory
        self.force = force
        self.offline = offline
        self.verbose = verbose
    }
}

public struct BuildResult: Sendable {
    public let app: URL
    public let dmg: URL?
    public let report: URL
}

public struct CommandResult: Sendable {
    public let output: String
    public let status: Int32
}

public struct ProcessRunner: Sendable {
    public let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    @discardableResult
    public func run(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil
    ) throws -> CommandResult {
        if verbose {
            print("  $ \(([executable] + arguments).map(shellQuoted).joined(separator: " "))")
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        do {
            try process.run()
        } catch {
            throw BuilderFailure.message("Could not run \(executable): \(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BuilderFailure.message(
                "Command failed (\(process.terminationStatus)): \(executable)" +
                    (detail.isEmpty ? "" : "\n\(detail)")
            )
        }

        return CommandResult(output: output, status: process.terminationStatus)
    }
}

private func shellQuoted(_ value: String) -> String {
    if value.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:".contains($0) }) {
        return value
    }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

public enum HostChecks {
    public static var isSupportedMacOS: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15
    }

    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
        #endif
    }

    public static var hasRosetta: Bool {
        guard isAppleSilicon else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

public enum GameLayout {
    private static let requiredNames = ["quasimorph.exe", "quasimorph_data", "unityplayer.dll"]

    public static func locateRoot(in searchRoot: URL) throws -> URL {
        let root = searchRoot.standardizedFileURL
        var candidates: [URL] = []

        if isValidRoot(root) {
            candidates.append(root)
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let item as URL in enumerator {
                let values = try item.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isDirectory == true else { continue }
                if isValidRoot(item) {
                    candidates.append(item)
                    enumerator.skipDescendants()
                }
            }
        }

        let unique = Array(Set(candidates.map(\.standardizedFileURL.path))).sorted()
        guard unique.count == 1 else {
            if unique.isEmpty {
                throw BuilderFailure.message(
                    "No Quasimorph game folder found. Expected Quasimorph.exe, Quasimorph_Data, and UnityPlayer.dll together."
                )
            }
            throw BuilderFailure.message("More than one Quasimorph game folder was found. Please select the correct folder directly.")
        }
        return URL(fileURLWithPath: unique[0], isDirectory: true)
    }

    public static func validateNoSymlinks(in root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: Set(keys)).isSymbolicLink == true {
                throw BuilderFailure.message("The game copy contains a symbolic link and was rejected for safety: \(item.lastPathComponent)")
            }
        }
    }

    public static func validateArchiveEntry(_ rawPath: String) throws {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        let lower = path.lowercased()
        let components = path.split(separator: "/", omittingEmptySubsequences: false)

        if path.hasPrefix("/") || path.hasPrefix("~") || lower.hasPrefix("file:") {
            throw BuilderFailure.message("Archive contains an unsafe absolute path: \(rawPath)")
        }
        if path.range(of: "^[A-Za-z]:", options: .regularExpression) != nil {
            throw BuilderFailure.message("Archive contains an unsafe Windows drive path: \(rawPath)")
        }
        if components.contains("..") {
            throw BuilderFailure.message("Archive contains an unsafe parent path: \(rawPath)")
        }
    }

    public static func validateSevenZipListing(_ listing: String) throws {
        var readingEntries = false
        for line in listing.split(separator: "\n") {
            if line == "----------" {
                readingEntries = true
                continue
            }
            if readingEntries, line == "Encrypted = +" {
                throw BuilderFailure.message("Password-protected archives are not supported. Extract it first, then select the game folder.")
            }
            guard readingEntries, line.hasPrefix("Path = ") else { continue }
            try validateArchiveEntry(String(line.dropFirst("Path = ".count)))
        }
        guard readingEntries else {
            throw BuilderFailure.message("Could not read the archive file list.")
        }
    }

    public static func detectedVersion(from source: URL) -> String? {
        let name = source.deletingPathExtension().lastPathComponent
        let pattern = #"(?i)(?:^|[^0-9])v?(\d+\.\d+(?:\.\d+)?)(?:[^0-9]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name)
        else { return nil }
        return String(name[range])
    }

    private static func isValidRoot(_ directory: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        let lowerNames = Set(names.map { $0.lowercased() })
        return requiredNames.allSatisfy(lowerNames.contains)
    }
}

public final class QuasimorphBuilder {
    public static let version = "0.3.0"

    private let fileManager = FileManager.default
    private let options: BuildOptions
    private let runner: ProcessRunner

    public init(options: BuildOptions) {
        self.options = options
        runner = ProcessRunner(verbose: options.verbose)
    }

    public func build() throws -> BuildResult {
        try preflight()
        try fileManager.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: options.cacheDirectory, withIntermediateDirectories: true)

        let work = fileManager.temporaryDirectory
            .appendingPathComponent("quasimorph-macos-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        if options.verbose { print("  Work directory: \(work.path)") }
        defer {
            if options.keepWorkDirectory {
                print("  Kept work directory: \(work.path)")
            } else {
                try? fileManager.removeItem(at: work)
            }
        }

        let dependencyStore = DependencyStore(
            cache: options.cacheDirectory,
            overrideDirectory: options.dependencyDirectory,
            offline: options.offline,
            runner: runner
        )
        let gameRoot: URL?
        let gameVersion: String?
        switch options.source {
        case let .gameFiles(source):
            print("[1/7] Reading your game copy")
            let root = try prepareGameSource(source, in: work, dependencyStore: dependencyStore)
            try GameLayout.validateNoSymlinks(in: root)
            gameRoot = root
            gameVersion = GameLayout.detectedVersion(from: source)
        case .steam:
            print("[1/7] Preparing the Steam edition")
            gameRoot = nil
            gameVersion = nil
        }

        print("[2/7] Getting verified macOS runtime")
        let templateArchive = try dependencyStore.file(for: LockedDependencies.template)
        let engineArchive = try dependencyStore.file(for: LockedDependencies.engine)

        print("[3/7] Assembling Quasimorph.app")
        let app = try assembleApp(
            work: work,
            gameVersion: gameVersion,
            templateArchive: templateArchive,
            engineArchive: engineArchive
        )

        print("[4/7] Initializing private Wine data")
        try initializePrefix(in: app)

        print("[5/7] Installing DXVK and locking file access")
        try installDXVK(in: app)
        try hardenPrefix(in: app)
        if let gameRoot {
            try copyGame(from: gameRoot, into: app)
        }

        print("[6/7] Signing and verifying the app")
        try signAndVerify(app)

        print("[7/7] Writing the app and DMG")
        let result = try publish(app: app, gameVersion: gameVersion, work: work)
        print("\nBuilt successfully:")
        print("  App: \(result.app.path)")
        if let dmg = result.dmg { print("  DMG: \(dmg.path)") }
        print("  Report: \(result.report.path)")
        return result
    }

    private func preflight() throws {
        guard HostChecks.isSupportedMacOS else {
            throw BuilderFailure.message(
                "Wine 11 requires macOS 15 or newer. On macOS 13 or 14, use release v0.2.1; it does not include the Cmd+Tab fix."
            )
        }
        guard HostChecks.isAppleSilicon else {
            throw BuilderFailure.message("This first release supports Apple Silicon Macs only.")
        }
        guard HostChecks.hasRosetta else {
            throw BuilderFailure.message(
                "Rosetta 2 is required. Install it with:\n/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
            )
        }

        if case let .gameFiles(source) = options.source {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                throw BuilderFailure.message("Game copy not found: \(source.path)")
            }
        }

        let parent = options.outputDirectory.deletingLastPathComponent()
        let capacity = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let capacity, capacity > 0, capacity < 8_000_000_000 {
            throw BuilderFailure.message("At least 8 GB of free disk space is required to build the app and DMG.")
        }
    }

    private func prepareGameSource(_ source: URL, in work: URL, dependencyStore: DependencyStore) throws -> URL {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            return try GameLayout.locateRoot(in: source)
        }

        if source.pathExtension.lowercased() == "exe" {
            guard source.lastPathComponent.lowercased() == "quasimorph.exe" else {
                throw BuilderFailure.message("Select Quasimorph.exe itself, not a Windows installer.")
            }
            return try GameLayout.locateRoot(in: source.deletingLastPathComponent())
        }

        let supported = ["rar", "7z", "zip", "tar", "xz"]
        guard supported.contains(source.pathExtension.lowercased()) else {
            throw BuilderFailure.message("Unsupported input. Use a RAR, 7Z, ZIP, extracted folder, or Quasimorph.exe.")
        }

        let sevenZip = try dependencyStore.sevenZipExecutable()
        let listing = try runner.run(sevenZip.path, ["l", "-slt", source.path]).output
        try GameLayout.validateSevenZipListing(listing)

        let extraction = work.appendingPathComponent("game", isDirectory: true)
        try fileManager.createDirectory(at: extraction, withIntermediateDirectories: true)
        try runner.run(sevenZip.path, ["x", "-y", "-bb0", "-o\(extraction.path)", source.path])
        return try GameLayout.locateRoot(in: extraction)
    }

    private func assembleApp(
        work: URL,
        gameVersion: String?,
        templateArchive: URL,
        engineArchive: URL
    ) throws -> URL {
        let templateRoot = work.appendingPathComponent("template", isDirectory: true)
        let engineRoot = work.appendingPathComponent("engine", isDirectory: true)
        try fileManager.createDirectory(at: templateRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: engineRoot, withIntermediateDirectories: true)
        try runner.run("/usr/bin/tar", ["-xf", templateArchive.path, "-C", templateRoot.path])
        try runner.run("/usr/bin/tar", ["-xf", engineArchive.path, "-C", engineRoot.path])

        let originalApp = templateRoot.appendingPathComponent("Template-1.0.11.app", isDirectory: true)
        let app = work.appendingPathComponent("Quasimorph.app", isDirectory: true)
        guard fileManager.fileExists(atPath: originalApp.path) else {
            throw BuilderFailure.message("Verified template did not contain Template-1.0.11.app.")
        }
        try fileManager.moveItem(at: originalApp, to: app)

        let engine = engineRoot.appendingPathComponent("Libraries/Wine", isDirectory: true)
        let dxvk = engineRoot.appendingPathComponent("Libraries/DXVK", isDirectory: true)
        let installedEngine = app.appendingPathComponent("Contents/SharedSupport/wswine", isDirectory: true)
        let installedDXVK = app.appendingPathComponent("Contents/SharedSupport/dxvk", isDirectory: true)
        guard fileManager.fileExists(atPath: engine.path) else {
            throw BuilderFailure.message("Verified runtime did not contain Libraries/Wine.")
        }
        guard fileManager.fileExists(atPath: dxvk.appendingPathComponent("x64/d3d11.dll").path) else {
            throw BuilderFailure.message("Verified runtime did not contain DXVK for macOS.")
        }
        try runner.run("/usr/bin/ditto", [engine.path, installedEngine.path])
        try runner.run("/usr/bin/ditto", [dxvk.path, installedDXVK.path])

        try configureInfoPlist(in: app, gameVersion: gameVersion)
        try installLauncher(in: app)
        return app
    }

    func configureInfoPlist(in app: URL, gameVersion: String?) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BuilderFailure.message("The wrapper Info.plist is invalid.")
        }

        plist["CFBundleExecutable"] = "launcher"
        plist["CFBundleIdentifier"] = switch options.source {
        case .gameFiles: "io.github.kvyb.QuasimorphForMacOS"
        case .steam: "io.github.kvyb.QuasimorphForMacOS.Steam"
        }
        plist["CFBundleName"] = "Quasimorph"
        plist["CFBundleDisplayName"] = "Quasimorph"
        plist["CFBundleShortVersionString"] = gameVersion ?? Self.version
        plist["CFBundleVersion"] = "1"
        plist["LSMinimumSystemVersion"] = "15.0"
        switch options.source {
        case .gameFiles:
            plist["Program Name and Path"] = "/Quasimorph/Quasimorph.exe"
        case .steam:
            plist["Program Name and Path"] = "/Program Files (x86)/Steam/steam.exe"
        }
        plist["DXMT"] = 0
        plist["DXVK"] = 1
        plist["D3DMETAL"] = 0
        plist["MOLTENVKCX"] = 0
        plist["Symlinks In User Folder"] = 0
        plist["WINEDEBUG"] = "-all"

        let removedKeys = [
            "NSBGOnly", "LSBackgroundOnly", "LSUIElement",
            "NSHighResolutionCapable",
            "Associations", "CFBundleDocumentTypes", "CLI Custom Commands",
            "NSAppTransportSecurity", "NSMainNibFile", "NSPrincipalClass",
            "NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription",
            "NSCameraUsageDescription", "NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription",
            "NSMicrophoneUsageDescription", "NSNetworkVolumesUsageDescription",
            "NSRemovableVolumesUsageDescription", "Symlink Desktop", "Symlink Downloads",
            "Symlink My Documents", "Symlink My Music", "Symlink My Pictures",
            "Symlink My Videos", "Symlink Templates"
        ]
        for key in removedKeys { plist.removeValue(forKey: key) }

        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: plistURL, options: .atomic)
    }

    private func installLauncher(in app: URL) throws {
        let launcher = app.appendingPathComponent("Contents/MacOS/launcher")
        if fileManager.fileExists(atPath: launcher.path) || (try? launcher.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try fileManager.removeItem(at: launcher)
        }
        try Launcher.script(for: options.source).write(to: launcher, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    }

    private func initializePrefix(in app: URL) throws {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let prefix = contents.appendingPathComponent("SharedSupport/prefix", isDirectory: true)
        try fileManager.createDirectory(at: prefix, withIntermediateDirectories: true)
        let wine = contents.appendingPathComponent("SharedSupport/wswine/bin/wine")
        let wineserver = contents.appendingPathComponent("SharedSupport/wswine/bin/wineserver")
        let environment = wineEnvironment(contents: contents)
        try runner.run(wine.path, ["wineboot", "-u"], environment: environment)
        try runner.run(wineserver.path, ["-w"], environment: environment)
    }

    private func installDXVK(in app: URL) throws {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let source = contents.appendingPathComponent("SharedSupport/dxvk", isDirectory: true)
        let system32 = contents.appendingPathComponent("SharedSupport/prefix/drive_c/windows/system32", isDirectory: true)
        let syswow64 = contents.appendingPathComponent("SharedSupport/prefix/drive_c/windows/syswow64", isDirectory: true)

        guard fileManager.fileExists(atPath: source.appendingPathComponent("x64/d3d11.dll").path),
              fileManager.fileExists(atPath: source.appendingPathComponent("x32/d3d11.dll").path)
        else {
            throw BuilderFailure.message("The verified runtime's DXVK payload is incomplete.")
        }
        try copyDLLs(from: source.appendingPathComponent("x64"), to: system32)
        try copyDLLs(from: source.appendingPathComponent("x32"), to: syswow64)
    }

    private func hardenPrefix(in app: URL) throws {
        let prefix = app.appendingPathComponent("Contents/SharedSupport/prefix", isDirectory: true)
        let dosDevices = prefix.appendingPathComponent("dosdevices", isDirectory: true)
        try fileManager.createDirectory(at: dosDevices, withIntermediateDirectories: true)

        for item in try fileManager.contentsOfDirectory(at: dosDevices, includingPropertiesForKeys: nil) {
            if item.lastPathComponent.lowercased() != "c:" {
                try fileManager.removeItem(at: item)
            }
        }

        let cDrive = dosDevices.appendingPathComponent("c:")
        if fileManager.fileExists(atPath: cDrive.path) || (try? cDrive.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try fileManager.removeItem(at: cDrive)
        }
        try fileManager.createSymbolicLink(atPath: cDrive.path, withDestinationPath: "../drive_c")

        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: users,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                enumerator.skipDescendants()
                try fileManager.removeItem(at: item)
                try fileManager.createDirectory(at: item, withIntermediateDirectories: true)
            }
        }
    }

    private func copyGame(from gameRoot: URL, into app: URL) throws {
        let destination = app.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/Quasimorph", isDirectory: true)
        try runner.run("/usr/bin/ditto", [gameRoot.path, destination.path])
    }

    private func signAndVerify(_ app: URL) throws {
        let signature = app.appendingPathComponent("Contents/_CodeSignature")
        if fileManager.fileExists(atPath: signature.path) {
            try fileManager.removeItem(at: signature)
        }
        try runner.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
        try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])

        let plistData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        guard plist?["NSBGOnly"] == nil else {
            throw BuilderFailure.message("Verification failed: NSBGOnly is still present.")
        }
        guard fileManager.fileExists(atPath: app.appendingPathComponent("Contents/SharedSupport/dxvk/x64/d3d11.dll").path),
              fileManager.fileExists(atPath: app.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/windows/system32/d3d11.dll").path)
        else {
            throw BuilderFailure.message("Verification failed: DXVK is missing.")
        }
        if case .gameFiles = options.source {
            guard fileManager.fileExists(atPath: app.appendingPathComponent("Contents/drive_c/Quasimorph/Quasimorph.exe").path) else {
                throw BuilderFailure.message("Verification failed: Quasimorph.exe is missing from the app.")
            }
        }
    }

    private func publish(app: URL, gameVersion: String?, work: URL) throws -> BuildResult {
        let outputApp = options.outputDirectory.appendingPathComponent("Quasimorph.app", isDirectory: true)
        let dmgName: String
        if case .steam = options.source {
            dmgName = "Quasimorph-Steam-macOS.dmg"
        } else {
            dmgName = gameVersion.map { "Quasimorph-macOS-v\($0).dmg" } ?? "Quasimorph-macOS.dmg"
        }
        let outputDMG = options.outputDirectory.appendingPathComponent(dmgName)
        let reportURL = options.outputDirectory.appendingPathComponent("BUILD-REPORT.txt")

        try prepareOutput(outputApp)
        if options.createDMG { try prepareOutput(outputDMG) }
        if fileManager.fileExists(atPath: reportURL.path), !options.force {
            throw BuilderFailure.message("Output already exists: \(reportURL.path). Use --force to replace it.")
        }
        try? fileManager.removeItem(at: reportURL)

        try runner.run("/usr/bin/ditto", [app.path, outputApp.path])
        var report = buildReport(gameVersion: gameVersion, dmgSHA: nil)
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        var dmg: URL?
        if options.createDMG {
            let dmgRoot = work.appendingPathComponent("dmg", isDirectory: true)
            try fileManager.createDirectory(at: dmgRoot, withIntermediateDirectories: true)
            try runner.run("/usr/bin/ditto", [outputApp.path, dmgRoot.appendingPathComponent("Quasimorph.app").path])
            try DmgReadme.text(for: options.source)
                .write(to: dmgRoot.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            try report.write(to: dmgRoot.appendingPathComponent("BUILD-REPORT.txt"), atomically: true, encoding: .utf8)
            try fileManager.createSymbolicLink(
                at: dmgRoot.appendingPathComponent("Applications"),
                withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
            try runner.run("/usr/bin/hdiutil", [
                "create", "-volname", "Quasimorph macOS", "-srcfolder", dmgRoot.path,
                "-ov", "-format", "UDZO", outputDMG.path
            ])
            let dmgSHA = try sha256(of: outputDMG)
            report = buildReport(gameVersion: gameVersion, dmgSHA: dmgSHA)
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            dmg = outputDMG
        }

        return BuildResult(app: outputApp, dmg: dmg, report: reportURL)
    }

    private func prepareOutput(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            guard options.force else {
                throw BuilderFailure.message("Output already exists: \(url.path). Use --force to replace it.")
            }
            try fileManager.removeItem(at: url)
        }
    }

    private func buildReport(gameVersion: String?, dmgSHA: String?) -> String {
        var lines = [
            "Quasimorph for macOS - local build report",
            "",
            "Builder: \(Self.version)",
            "Game version label: \(gameVersion ?? "not detected")",
            "Input: \(sourceReportLabel)",
            "Template: \(LockedDependencies.template.version)",
            "Template SHA-256: \(LockedDependencies.template.sha256)",
            "Engine: \(LockedDependencies.engine.version)",
            "Engine SHA-256: \(LockedDependencies.engine.sha256)",
            "DXVK: 1.10.3 macOS build from the verified runtime",
            "Renderer: DXVK / Direct3D 11",
            "Host drive mappings: C: only",
            "Code signature: ad hoc, verified",
            "Game launched during build: no"
        ]
        if let dmgSHA { lines.append("DMG SHA-256: \(dmgSHA)") }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private var sourceReportLabel: String {
        switch options.source {
        case .gameFiles: "local user-provided copy (path intentionally omitted)"
        case .steam: "Steam client bootstrap (game downloaded from the user's Steam account)"
        }
    }

    private func wineEnvironment(contents: URL) -> [String: String] {
        [
            "WINEPREFIX": contents.appendingPathComponent("SharedSupport/prefix").path,
            "PATH": contents.appendingPathComponent("SharedSupport/wswine/bin").path + ":/usr/bin:/bin",
            "DYLD_FALLBACK_LIBRARY_PATH": contents.appendingPathComponent("SharedSupport/wswine/lib").path + ":" + contents.appendingPathComponent("Frameworks").path,
            "WINEDLLOVERRIDES": "dxgi,d3d11,d3d10core=n,b;mscoree,mshtml=",
            "WINEARCH": "win64",
            "WINEESYNC": "1",
            "WINEMSYNC": "1",
            "WINEDEBUG": "-all",
            "DXVK_LOG_LEVEL": "none",
            "MVK_CONFIG_LOG_LEVEL": "0"
        ]
    }

    private func copyDLLs(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) where item.pathExtension.lowercased() == "dll" {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: item, to: target)
        }
    }
}

private final class DependencyStore {
    private let cache: URL
    private let overrideDirectory: URL?
    private let offline: Bool
    private let runner: ProcessRunner
    private let fileManager = FileManager.default

    init(cache: URL, overrideDirectory: URL?, offline: Bool, runner: ProcessRunner) {
        self.cache = cache
        self.overrideDirectory = overrideDirectory
        self.offline = offline
        self.runner = runner
    }

    func file(for dependency: LockedDependency) throws -> URL {
        if let overrideDirectory {
            let override = overrideDirectory.appendingPathComponent(dependency.fileName)
            if fileManager.fileExists(atPath: override.path) {
                try verify(override, dependency: dependency)
                return override
            }
        }

        let cached = cache.appendingPathComponent(dependency.fileName)
        if fileManager.fileExists(atPath: cached.path) {
            do {
                try verify(cached, dependency: dependency)
                return cached
            } catch {
                guard !offline else { throw error }
                try fileManager.removeItem(at: cached)
            }
        }

        guard !offline else {
            throw BuilderFailure.message("Missing offline dependency: \(dependency.fileName)")
        }

        print("  Downloading \(dependency.name) \(dependency.version)")
        let temporary = cache.appendingPathComponent(".\(dependency.fileName).download")
        try? fileManager.removeItem(at: temporary)
        do {
            try runner.run("/usr/bin/curl", [
                "--fail", "--location", "--progress-bar",
                "--output", temporary.path, dependency.url.absoluteString
            ])
            try verify(temporary, dependency: dependency)
            try fileManager.moveItem(at: temporary, to: cached)
            return cached
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func sevenZipExecutable() throws -> URL {
        let archive = try file(for: LockedDependencies.sevenZip)
        let toolRoot = cache.appendingPathComponent("7zip-\(LockedDependencies.sevenZip.version)", isDirectory: true)
        let executable = toolRoot.appendingPathComponent("7zz")
        if fileManager.isExecutableFile(atPath: executable.path) { return executable }

        try? fileManager.removeItem(at: toolRoot)
        try fileManager.createDirectory(at: toolRoot, withIntermediateDirectories: true)
        try runner.run("/usr/bin/tar", ["-xf", archive.path, "-C", toolRoot.path])
        guard fileManager.fileExists(atPath: executable.path) else {
            throw BuilderFailure.message("7-Zip archive did not contain 7zz.")
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    private func verify(_ file: URL, dependency: LockedDependency) throws {
        let actual = try sha256(of: file)
        guard actual == dependency.sha256 else {
            throw BuilderFailure.message(
                "Checksum mismatch for \(dependency.fileName).\nExpected: \(dependency.sha256)\nActual:   \(actual)"
            )
        }
    }
}

public enum Launcher {
    public static func script(for source: BuildSource) -> String {
        switch source {
        case .gameFiles: gameFilesScript
        case .steam: steamScript
        }
    }

    public static let gameFilesScript = #"""
#!/bin/sh

CONTENTS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PREFIX="$CONTENTS_DIR/SharedSupport/prefix"
WINDOWS_USER=""
for USER_DIR in "$PREFIX"/drive_c/users/*; do
  [ -d "$USER_DIR" ] || continue
  [ "$(basename "$USER_DIR")" = "Public" ] && continue
  WINDOWS_USER="$(basename "$USER_DIR")"
  break
done
[ -n "$WINDOWS_USER" ] || WINDOWS_USER="$(id -un)"
LOG_DIR="$PREFIX/drive_c/users/$WINDOWS_USER/AppData/LocalLow/Quasimorph-macOS"

mkdir -p "$LOG_DIR"

export WINEPREFIX="$PREFIX"
export PATH="$CONTENTS_DIR/SharedSupport/wswine/bin:/usr/bin:/bin"
export DYLD_FALLBACK_LIBRARY_PATH="$CONTENTS_DIR/SharedSupport/wswine/lib:$CONTENTS_DIR/Frameworks"
export WINEDLLOVERRIDES="dxgi,d3d11,d3d10core=n,b;mscoree,mshtml="
export WINEESYNC=1
export WINEMSYNC=1
export WINEDEBUG=-all
export DXVK_LOG_LEVEL=none
export MVK_CONFIG_LOG_LEVEL=0

cd "$CONTENTS_DIR/drive_c/Quasimorph" || exit 1
exec "$CONTENTS_DIR/SharedSupport/wswine/bin/wine" \
  'C:\Quasimorph\Quasimorph.exe' \
  -force-d3d11 \
  -logFile "C:\\users\\$WINDOWS_USER\\AppData\\LocalLow\\Quasimorph-macOS\\Player.log" \
  "$@"
"""#

    public static var steamScript: String {
        steamScriptTemplate
            .replacingOccurrences(of: "__STEAM_INSTALLER_URL__", with: LockedDependencies.steamInstaller.url.absoluteString)
            .replacingOccurrences(of: "__STEAM_INSTALLER_SHA256__", with: LockedDependencies.steamInstaller.sha256)
    }

    private static let steamScriptTemplate = #"""
#!/bin/sh

CONTENTS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PREFIX="$CONTENTS_DIR/SharedSupport/prefix"
WINE="$CONTENTS_DIR/SharedSupport/wswine/bin/wine"
STEAM_DIR="$PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/steam.exe"
GAME_EXE="$STEAM_DIR/steamapps/common/Quasimorph/Quasimorph.exe"
WINDOWS_USER=""
for USER_DIR in "$PREFIX"/drive_c/users/*; do
  [ -d "$USER_DIR" ] || continue
  [ "$(basename "$USER_DIR")" = "Public" ] && continue
  WINDOWS_USER="$(basename "$USER_DIR")"
  break
done
[ -n "$WINDOWS_USER" ] || WINDOWS_USER="$(id -un)"
SETUP_DIR="$PREFIX/drive_c/users/$WINDOWS_USER/AppData/Local/Temp"
SETUP="$SETUP_DIR/SteamSetup.exe"

export WINEPREFIX="$PREFIX"
export PATH="$CONTENTS_DIR/SharedSupport/wswine/bin:/usr/bin:/bin"
export DYLD_FALLBACK_LIBRARY_PATH="$CONTENTS_DIR/SharedSupport/wswine/lib:$CONTENTS_DIR/Frameworks"
export WINEDLLOVERRIDES="dxgi,d3d11,d3d10core=n,b;mscoree,mshtml="
export WINEESYNC=1
export WINEMSYNC=1
export WINEDEBUG=-all
export DXVK_LOG_LEVEL=none
export MVK_CONFIG_LOG_LEVEL=0

show_message() {
  /usr/bin/osascript - "$1" <<'APPLESCRIPT'
on run argv
  display dialog (item 1 of argv) with title "Quasimorph for macOS" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

if [ ! -f "$STEAM_EXE" ]; then
  show_message "First launch will install Valve's official Steam client. Sign in to the account that owns Quasimorph when Steam opens."
  mkdir -p "$SETUP_DIR"

  if ! /usr/bin/curl --fail --location --progress-bar --output "$SETUP" \
    '__STEAM_INSTALLER_URL__'; then
    show_message "Steam could not be downloaded. Check your internet connection and open Quasimorph again."
    exit 1
  fi

  ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$SETUP" | /usr/bin/awk '{print $1}')"
  if [ "$ACTUAL_SHA" != '__STEAM_INSTALLER_SHA256__' ]; then
    rm -f "$SETUP"
    show_message "Valve changed the Steam installer. For safety, update Quasimorph for macOS before trying again."
    exit 1
  fi

  if ! "$WINE" "$SETUP" /S; then
    show_message "Steam installation failed. Open Quasimorph again to retry."
    exit 1
  fi
  rm -f "$SETUP"

  if [ ! -f "$STEAM_EXE" ]; then
    show_message "Steam installation did not finish. Open Quasimorph again to retry."
    exit 1
  fi
fi

cd "$STEAM_DIR" || exit 1

if [ ! -f "$GAME_EXE" ]; then
  show_message "Steam will open the Quasimorph install screen. Sign in, install the game, then open this app again to play."
  exec "$WINE" "$STEAM_EXE" 'steam://install/2059170'
fi

exec "$WINE" "$STEAM_EXE" \
  -applaunch 2059170 \
  -force-d3d11 \
  "$@"
"""#
}

private enum DmgReadme {
    static func text(for source: BuildSource) -> String {
        switch source {
        case .gameFiles:
            """
            QUASIMORPH FOR MACOS

            1. Drag Quasimorph.app to Applications.
            2. Open it.
            3. If macOS blocks the first launch, right-click the app and choose Open.

            Logs:
            Quasimorph.app/Contents/SharedSupport/prefix/drive_c/users/crossover/AppData/LocalLow/Quasimorph-macOS/Player.log

            This is an unofficial compatibility wrapper built from your own Windows copy.
            Do not redistribute this DMG: it contains your copy of the game.
            """
        case .steam:
            """
            QUASIMORPH FOR MACOS - STEAM

            1. Drag Quasimorph.app to Applications.
            2. Open it.
            3. Steam installs. Sign in and install Quasimorph when prompted.
            4. Open Quasimorph.app again to play.

            Your password and Steam Guard stay inside Valve's Steam client.
            This is an unofficial compatibility wrapper. No game files are included.
            """
        }
    }
}

public func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
