import Foundation
import XCTest
@testable import QuasimorphBuilder

final class BuilderTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("quasimorph-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporary)
    }

    func testFindsPortableGameRootInsideArchiveFolder() throws {
        let root = temporary.appendingPathComponent("release/Quasimorph", isDirectory: true)
        try makeGame(at: root)

        XCTAssertEqual(try GameLayout.locateRoot(in: temporary).path, root.path)
    }

    func testRejectsIncompleteGameCopy() throws {
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try Data().write(to: temporary.appendingPathComponent("Quasimorph.exe"))

        XCTAssertThrowsError(try GameLayout.locateRoot(in: temporary))
    }

    func testRejectsAmbiguousGameCopies() throws {
        try makeGame(at: temporary.appendingPathComponent("one", isDirectory: true))
        try makeGame(at: temporary.appendingPathComponent("two", isDirectory: true))

        XCTAssertThrowsError(try GameLayout.locateRoot(in: temporary))
    }

    func testRejectsArchiveTraversalAndAbsolutePaths() {
        XCTAssertThrowsError(try GameLayout.validateArchiveEntry("../escape/file"))
        XCTAssertThrowsError(try GameLayout.validateArchiveEntry("folder\\..\\escape"))
        XCTAssertThrowsError(try GameLayout.validateArchiveEntry("/tmp/escape"))
        XCTAssertThrowsError(try GameLayout.validateArchiveEntry("C:\\escape"))
        XCTAssertNoThrow(try GameLayout.validateArchiveEntry("Quasimorph/Quasimorph.exe"))
    }

    func testSevenZipListingIgnoresArchiveHeaderButChecksEntries() {
        let safe = """
        Listing archive: /Users/me/Downloads/Quasimorph.rar
        --
        Path = /Users/me/Downloads/Quasimorph.rar
        Type = Rar
        ----------
        Path = Quasimorph/Quasimorph.exe
        """
        XCTAssertNoThrow(try GameLayout.validateSevenZipListing(safe))

        let unsafe = safe + "\nPath = ../escape\n"
        XCTAssertThrowsError(try GameLayout.validateSevenZipListing(unsafe))

        let encrypted = safe + "\nEncrypted = +\n"
        XCTAssertThrowsError(try GameLayout.validateSevenZipListing(encrypted))
    }

    func testDetectsVersionWithoutGuessingUnrelatedNumbers() {
        XCTAssertEqual(
            GameLayout.detectedVersion(from: URL(fileURLWithPath: "/tmp/Quasimorph.v1.0.rar")),
            "1.0"
        )
        XCTAssertNil(GameLayout.detectedVersion(from: URL(fileURLWithPath: "/tmp/Quasimorph.rar")))
    }

    func testLauncherUsesForegroundD3D11AndPrivatePrefix() {
        let script = Launcher.script(for: .gameFiles(temporary))
        XCTAssertTrue(script.contains("-force-d3d11"))
        XCTAssertTrue(script.contains("SharedSupport/prefix"))
        XCTAssertTrue(script.contains("WINEDEBUG=-all"))
        XCTAssertTrue(script.contains("WINEDLLOVERRIDES=\"dxgi,d3d11,d3d10core=n,b;mscoree,mshtml=\""))
        XCTAssertTrue(script.contains("DXVK_LOG_LEVEL=none"))
        XCTAssertTrue(script.contains("MVK_CONFIG_LOG_LEVEL=0"))
        XCTAssertTrue(script.contains("WINDOWS_USER"))
        XCTAssertFalse(script.contains("NSBGOnly"))
        XCTAssertFalse(script.contains("native,builtin"))
        XCTAssertFalse(script.contains("DXMT_LOG_LEVEL"))
        XCTAssertFalse(script.contains("DXMT_LOG_PATH"))
        XCTAssertFalse(script.contains("wine.log"))
    }

    func testSteamLauncherUsesOfficialClientAndDoesNotHandleCredentials() {
        let script = Launcher.script(for: .steam)
        XCTAssertTrue(script.contains(LockedDependencies.steamInstaller.url.absoluteString))
        XCTAssertTrue(script.contains(LockedDependencies.steamInstaller.sha256))
        XCTAssertTrue(script.contains("steam://install/2059170"))
        XCTAssertTrue(script.contains("-applaunch 2059170"))
        XCTAssertTrue(script.contains("-force-d3d11"))
        XCTAssertTrue(script.contains("WINEDEBUG=-all"))
        XCTAssertTrue(script.contains("WINEDLLOVERRIDES=\"dxgi,d3d11,d3d10core=n,b;mscoree,mshtml=\""))
        XCTAssertTrue(script.contains("DXVK_LOG_LEVEL=none"))
        XCTAssertTrue(script.contains("MVK_CONFIG_LOG_LEVEL=0"))
        XCTAssertTrue(script.contains("WINDOWS_USER"))
        XCTAssertFalse(script.lowercased().contains("+password"))
        XCTAssertFalse(script.contains("DXMT_LOG_LEVEL"))
        XCTAssertFalse(script.contains("DXMT_LOG_PATH"))
        XCTAssertFalse(script.contains("wine.log"))
    }

    func testAppPlistRemovesRetinaFlagForWineMouseInput() throws {
        let app = temporary.appendingPathComponent("Quasimorph.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let plistURL = contents.appendingPathComponent("Info.plist")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let input: [String: Any] = ["NSHighResolutionCapable": true]
        try PropertyListSerialization.data(fromPropertyList: input, format: .xml, options: 0).write(to: plistURL)

        let options = BuildOptions(source: .gameFiles(temporary), outputDirectory: temporary, cacheDirectory: temporary)
        try QuasimorphBuilder(options: options).configureInfoPlist(in: app, gameVersion: "1.0")

        let data = try Data(contentsOf: plistURL)
        let output = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertNil(output["NSHighResolutionCapable"])
        XCTAssertEqual(output["DXVK"] as? Int, 1)
        XCTAssertEqual(output["DXMT"] as? Int, 0)
        XCTAssertEqual(output["LSMinimumSystemVersion"] as? String, "15.0")
    }

    func testSteamAppPlistTargetsSteam() throws {
        let app = temporary.appendingPathComponent("Quasimorph.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let plistURL = contents.appendingPathComponent("Info.plist")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: [:], format: .xml, options: 0).write(to: plistURL)

        let options = BuildOptions(source: .steam, outputDirectory: temporary, cacheDirectory: temporary)
        try QuasimorphBuilder(options: options).configureInfoPlist(in: app, gameVersion: nil)

        let data = try Data(contentsOf: plistURL)
        let output = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(output["Program Name and Path"] as? String, "/Program Files (x86)/Steam/steam.exe")
        XCTAssertEqual(output["CFBundleIdentifier"] as? String, "io.github.kvyb.QuasimorphForMacOS.Steam")
        XCTAssertEqual(output["CFBundleShortVersionString"] as? String, QuasimorphBuilder.version)
    }

    func testDependencyLockHasUniqueFilesAndSHA256Values() {
        XCTAssertEqual(Set(LockedDependencies.all.map(\.fileName)).count, LockedDependencies.all.count)
        for dependency in LockedDependencies.all {
            XCTAssertEqual(dependency.sha256.count, 64)
            XCTAssertNotNil(dependency.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression))
            XCTAssertEqual(dependency.url.scheme, "https")
        }
    }

    func testProcessRunnerWorksWithoutCurrentDirectory() throws {
        let result = try ProcessRunner().run("/usr/bin/printf", ["ok"])
        XCTAssertEqual(result.output, "ok")
    }

    private func makeGame(at root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Quasimorph_Data"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("Quasimorph.exe"))
        try Data().write(to: root.appendingPathComponent("UnityPlayer.dll"))
    }
}
