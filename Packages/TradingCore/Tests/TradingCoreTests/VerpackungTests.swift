#if os(macOS)
import Foundation
import Testing

/// Echte Git-Exporte, aber keine Xcode-Bauten, Signierung oder Notarisierung.
@Suite struct VerpackungTests {
    private struct Probe {
        let basis: URL
        let repo: URL
        let umgebung: [String: String]

        init() throws {
            basis = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("verpackung-\(UUID().uuidString)")
            repo = basis.appendingPathComponent("Repo mit Leerzeichen")
            umgebung = [
                "PATH": basis.appendingPathComponent("werkzeuge").path + ":/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": basis.appendingPathComponent("temp").path,
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                "HENRY_VERSION": "0.3.0", "HENRY_BUILDNUMMER": "42",
                "PRUEF_BASIS": basis.path
            ]
            for ordner in [repo, basis.appendingPathComponent("werkzeuge"), basis.appendingPathComponent("temp")] {
                try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            }
        }

        func schreibe(_ pfad: String, _ inhalt: String, ausfuehrbar: Bool = false) throws {
            let datei = basis.appendingPathComponent(pfad)
            try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
            try inhalt.write(to: datei, atomically: true, encoding: .utf8)
            if ausfuehrbar { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: datei.path) }
        }

        func lies(_ pfad: String) throws -> String {
            try String(contentsOf: basis.appendingPathComponent(pfad), encoding: .utf8)
        }

        func lauf(_ argumente: [String], zusaetze: [String: String] = [:]) throws -> (status: Int32, ausgabe: String) {
            let prozess = Process()
            prozess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            prozess.arguments = argumente
            prozess.currentDirectoryURL = repo
            prozess.environment = umgebung.merging(zusaetze) { _, neu in neu }
            let ausgabe = Pipe()
            prozess.standardOutput = ausgabe
            prozess.standardError = ausgabe
            try prozess.run()
            let daten = ausgabe.fileHandleForReading.readDataToEndOfFile()
            prozess.waitUntilExit()
            return (prozess.terminationStatus, String(decoding: daten, as: UTF8.self))
        }

        func git(_ argumente: [String]) throws {
            let ergebnis = try lauf(["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false",
                                     "-c", "user.name=Verpackungstest", "-c", "user.email=test@example.invalid"] + argumente)
            try #require(ergebnis.status == 0, "\(ergebnis.ausgabe)")
        }

        func vorbereiten() throws {
            var wurzel = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { wurzel.deleteLastPathComponent() }
            let skript = try String(contentsOf: wurzel.appendingPathComponent("scripts/app_verpacken.sh"), encoding: .utf8)
            try schreibe("Repo mit Leerzeichen/scripts/app_verpacken.sh", skript)
            try schreibe("Repo mit Leerzeichen/.gitignore", "*.pdf\n*.csv\n*.html\n.build/\nLocal.xcconfig\nbuild/\n")
            for pfad in ["App/Resources/versioniert.txt", "App/Sources/App.swift", "Packages/TradingConnector/Package.swift",
                         "Config/Base.xcconfig", "project.yml", "App/TradingBuddy-macOS.entitlements"] {
                try schreibe("Repo mit Leerzeichen/\(pfad)", "versioniert\n")
            }
            try schreibe("Repo mit Leerzeichen/Connector/manifest.json", "{\"version\":\"0.3.0\"}\n")
            try git(["init", "-q"])
            try git(["add", "."])
            try git(["commit", "-qm", "Teststand"])

            try schreibe("werkzeuge/xcodegen", """
                #!/bin/bash
                set -eu
                pwd -P > "$PRUEF_BASIS/app-quelle"
                find App Packages Connector Config -type f | sort > "$PRUEF_BASIS/app-dateien"
                cat App/Resources/versioniert.txt > "$PRUEF_BASIS/ressource"
                """, ausfuehrbar: true)
            try schreibe("werkzeuge/xcodebuild", """
                #!/bin/bash
                set -eu
                printf '%s\\n' "$@" > "$PRUEF_BASIS/bauargumente"
                while [ "$1" != "-derivedDataPath" ]; do shift; done
                app="$2/Build/Products/Release/Henry.app/Contents"
                mkdir -p "$app/Resources"
                cat > "$app/Info.plist" <<'PLIST'
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict>
                <key>CFBundleShortVersionString</key><string>0.3.0</string>
                <key>CFBundleVersion</key><string>42</string>
                </dict></plist>
                PLIST
                """, ausfuehrbar: true)
            try schreibe("werkzeuge/swift", """
                #!/bin/bash
                set -eu
                pwd -P > "$PRUEF_BASIS/connector-quelle"
                find App Packages Connector Config -type f | sort > "$PRUEF_BASIS/connector-dateien"
                if [ "${PRUEF_NOTAR:-}" = 1 ]; then
                    echo "$PRUEF_BASIS/server"
                    exit 0
                fi
                exit 73
                """, ausfuehrbar: true)
        }
    }

    @Test func ignorierteDateienErreichenWederAppNochConnector() throws {
        let probe = try Probe()
        defer { try? FileManager.default.removeItem(at: probe.basis) }
        try probe.vorbereiten()
        let lokal = ["App/Resources/privat.pdf", "App/Resources/privat.csv", "App/Resources/Unterordner/privat.html",
                     "App/Sources/privat.html", "Packages/TradingConnector/.build/alt", "Connector/privat.csv",
                     "Config/Local.xcconfig"]
        for pfad in lokal { try probe.schreibe("Repo mit Leerzeichen/\(pfad)", "nur lokal\n") }
        let ergebnis = try probe.lauf(["bash", "scripts/app_verpacken.sh"])
        try #require(ergebnis.status == 73, "\(ergebnis.ausgabe)")
        let appQuelle = try probe.lies("app-quelle").trimmingCharacters(in: .whitespacesAndNewlines)
        let connectorQuelle = try probe.lies("connector-quelle").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(appQuelle != probe.repo.resolvingSymlinksInPath().path)
        #expect(appQuelle == connectorQuelle)
        #expect(!FileManager.default.fileExists(atPath: appQuelle))
        #expect(try probe.lies("ressource") == "versioniert\n")
        for liste in ["app-dateien", "connector-dateien"] {
            let dateien = try probe.lies(liste).split(separator: "\n").map(String.init)
            #expect(dateien.contains("App/Resources/versioniert.txt"))
            for pfad in lokal { #expect(!dateien.contains(pfad)) }
        }
        let argumente = try probe.lies("bauargumente").split(separator: "\n").map(String.init)
        #expect(argumente.contains("MARKETING_VERSION=0.3.0"))
        #expect(argumente.contains("CURRENT_PROJECT_VERSION=42"))
        #expect(argumente.contains(probe.repo.path + "/build/release-derived"))
        #expect(FileManager.default.fileExists(atPath: probe.repo.appendingPathComponent("build/verteilung/Henry.app").path))
        for pfad in lokal { #expect(try probe.lies("Repo mit Leerzeichen/\(pfad)") == "nur lokal\n") }
    }

    @Test(arguments: [false, true]) func geaendertesVerpackungsskriptBrichtVorDemBauAb(vorgemerkt: Bool) throws {
        let probe = try Probe()
        defer { try? FileManager.default.removeItem(at: probe.basis) }
        try probe.vorbereiten()
        let pfad = "Repo mit Leerzeichen/scripts/app_verpacken.sh"
        try probe.schreibe(pfad, probe.lies(pfad) + "\n# Lokale Anpassung\n")
        if vorgemerkt { try probe.git(["add", "scripts/app_verpacken.sh"]) }
        let ergebnis = try probe.lauf(["bash", "scripts/app_verpacken.sh"])
        #expect(ergebnis.status == 1)
        #expect(ergebnis.ausgabe.contains("scripts/app_verpacken.sh"))
        #expect(!FileManager.default.fileExists(atPath: probe.basis.appendingPathComponent("app-quelle").path))
    }

    @Test func neueBuildEingabeBrichtWeiterhinAb() throws {
        let probe = try Probe()
        defer { try? FileManager.default.removeItem(at: probe.basis) }
        try probe.vorbereiten()
        try probe.schreibe("Repo mit Leerzeichen/App/Resources/neu.txt", "lokal\n")
        let ergebnis = try probe.lauf(["bash", "scripts/app_verpacken.sh"])
        #expect(ergebnis.status == 1)
        #expect(ergebnis.ausgabe.contains("App/Resources/neu.txt"))
        #expect(!FileManager.default.fileExists(atPath: probe.basis.appendingPathComponent("app-quelle").path))
    }

    @Test(arguments: [false, true]) func schluesselbundPfadBleibtErhalten(absolut: Bool) throws {
        let probe = try Probe()
        defer { try? FileManager.default.removeItem(at: probe.basis) }
        try probe.vorbereiten()
        try probe.schreibe("server/trading-buddy-mcp", "Testprogramm\n")
        try probe.schreibe("werkzeuge/lipo", "#!/bin/bash\necho 'arm64 x86_64'\n", ausfuehrbar: true)
        try probe.schreibe("werkzeuge/codesign", "#!/bin/bash\nexit 0\n", ausfuehrbar: true)
        try probe.schreibe("werkzeuge/xcrun", """
            #!/bin/bash
            printf '%s\\n' "$@" > "$PRUEF_BASIS/notarargumente"
            echo '{"status":"Rejected"}'
            """, ausfuehrbar: true)
        let erwartet = probe.repo.appendingPathComponent("build/notar.keychain-db").path
        let ergebnis = try probe.lauf(["bash", "scripts/app_verpacken.sh"], zusaetze: [
            "PRUEF_NOTAR": "1", "GITHUB_ACTIONS": "true", "HENRY_SIGNIERUNG": "Testidentitaet",
            "HENRY_NOTAR_PROFIL": "Testprofil", "HENRY_NOTAR_KEYCHAIN": absolut ? erwartet : "build/notar.keychain-db"
        ])
        #expect(ergebnis.status == 1)
        let argumente = try probe.lies("notarargumente").split(separator: "\n").map(String.init)
        let keychain = try #require(argumente.firstIndex(of: "--keychain"))
        try #require(argumente.indices.contains(keychain + 1))
        #expect(argumente[keychain + 1] == erwartet)
        let profil = try #require(argumente.firstIndex(of: "--keychain-profile"))
        try #require(argumente.indices.contains(profil + 1))
        #expect(argumente[profil + 1] == "Testprofil")
    }
}
#endif
