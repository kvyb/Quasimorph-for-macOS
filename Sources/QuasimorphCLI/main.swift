import AppKit
import Foundation
import QuasimorphBuilder

private let help = """
Quasimorph for macOS \(QuasimorphBuilder.version)

Build a macOS app for your own Windows or Steam copy of Quasimorph.

USAGE
  quasimorph-macos build /absolute/path/Quasimorph.rar
  quasimorph-macos build                         # opens a Finder picker
  quasimorph-macos steam                         # Steam owns and installs the game
  quasimorph-macos doctor

OPTIONS
  --output PATH          Output folder (default: ~/Desktop/Quasimorph macOS)
  --cache PATH           Dependency cache folder
  --dependencies-dir P   Use matching dependency archives from this folder
  --no-dmg               Build only Quasimorph.app
  --offline              Never download dependencies
  --keep-workdir         Keep temporary files for debugging
  --force                Replace an existing builder output
  --verbose              Print commands
  -h, --help             Show this help

INPUTS
  Local: RAR, 7Z, ZIP, an extracted folder, or Quasimorph.exe.
  Steam: no file needed. Sign in through Valve's Steam client on first launch.
"""

private func expandedURL(_ path: String, isDirectory: Bool = false) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: isDirectory).standardizedFileURL
}

private func chooseSource() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Choose your Windows copy of Quasimorph"
    panel.message = "Select a RAR, 7Z, ZIP, Quasimorph.exe, or extracted game folder."
    panel.prompt = "Choose"
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
}

private func doctor() {
    print("Quasimorph for macOS doctor")
    print("  Apple Silicon: \(HostChecks.isAppleSilicon ? "OK" : "NOT SUPPORTED")")
    print("  Rosetta 2:     \(HostChecks.hasRosetta ? "OK" : "MISSING")")
    print("  curl:          \(FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") ? "OK" : "MISSING")")
    print("  hdiutil:       \(FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil") ? "OK" : "MISSING")")
}

private func parseBuild(_ rawArguments: [String], steam: Bool = false) throws -> BuildOptions? {
    var source: URL?
    var output = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/Quasimorph macOS", isDirectory: true)
    var cache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/QuasimorphForMacOS", isDirectory: true)
    var dependencies: URL?
    var createDMG = true
    var keepWorkdir = false
    var force = false
    var offline = false
    var verbose = false

    var index = 0
    while index < rawArguments.count {
        let argument = rawArguments[index]
        switch argument {
        case "-h", "--help":
            print(help)
            return nil
        case "--output", "--cache", "--dependencies-dir":
            guard index + 1 < rawArguments.count else {
                throw BuilderFailure.message("\(argument) requires a path.")
            }
            index += 1
            let value = expandedURL(rawArguments[index], isDirectory: true)
            if argument == "--output" { output = value }
            if argument == "--cache" { cache = value }
            if argument == "--dependencies-dir" { dependencies = value }
        case "--no-dmg": createDMG = false
        case "--keep-workdir": keepWorkdir = true
        case "--force": force = true
        case "--offline": offline = true
        case "--verbose": verbose = true
        default:
            if argument.hasPrefix("-") {
                throw BuilderFailure.message("Unknown option: \(argument)")
            }
            guard source == nil else {
                throw BuilderFailure.message("Only one game path can be supplied.")
            }
            guard !steam else {
                throw BuilderFailure.message("Steam mode does not take a game path. Use: quasimorph-macos steam")
            }
            source = expandedURL(argument)
        }
        index += 1
    }

    let buildSource: BuildSource
    if steam {
        buildSource = .steam
    } else {
        if source == nil { source = chooseSource() }
        guard let source else { return nil }
        buildSource = .gameFiles(source)
    }
    return BuildOptions(
        source: buildSource,
        outputDirectory: output,
        cacheDirectory: cache,
        dependencyDirectory: dependencies,
        createDMG: createDMG,
        keepWorkDirectory: keepWorkdir,
        force: force,
        offline: offline,
        verbose: verbose
    )
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments[0] == "-h" || arguments[0] == "--help" || arguments[0] == "help" {
        print(help)
    } else if arguments[0] == "--version" || arguments[0] == "version" {
        print(QuasimorphBuilder.version)
    } else if arguments[0] == "doctor" {
        doctor()
    } else {
        let steam = arguments[0] == "steam"
        if arguments[0] == "build" || steam { arguments.removeFirst() }
        if let options = try parseBuild(arguments, steam: steam) {
            _ = try QuasimorphBuilder(options: options).build()
        }
    }
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    FileHandle.standardError.write(Data("\nError: \(message)\n".utf8))
    exit(1)
}
