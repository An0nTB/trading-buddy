import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Eine offene WebSocket-Verbindung, nur Textnachrichten. Tests setzen eine aufgezeichnete Verbindung ein.
public protocol WebSocketVerbindung: Sendable {
    func sende(_ text: String) async throws
    func empfange() async throws -> String
    func schliesse()
}

/// Baut eine Verbindung zu einer Adresse.
public typealias WebSocketFabrik = @Sendable (URL) async throws -> any WebSocketVerbindung

public enum WebSocketFehler: Error, Sendable, Equatable {
    case unbekannteNachricht
}

/// Verbindung über `URLSessionWebSocketTask` aus Foundation, auf macOS und iOS gleich.
/// Die App braucht in der Sandbox die Berechtigung für ausgehende Verbindungen (com.apple.security.network.client).
public final class URLSessionVerbindung: WebSocketVerbindung, @unchecked Sendable {
    // @unchecked: URLSessionWebSocketTask ist laut Apple threadsicher, aber nicht als Sendable markiert.
    private let aufgabe: URLSessionWebSocketTask

    public init(url: URL, session: URLSession = .shared) {
        aufgabe = session.webSocketTask(with: url)
        aufgabe.resume()
    }

    public static let fabrik: WebSocketFabrik = { url in URLSessionVerbindung(url: url) }

    public func sende(_ text: String) async throws {
        try await withCheckedThrowingContinuation { (fortsetzung: CheckedContinuation<Void, Error>) in
            self.aufgabe.send(.string(text)) { fehler in
                if let fehler { fortsetzung.resume(throwing: fehler) } else { fortsetzung.resume() }
            }
        }
    }

    public func empfange() async throws -> String {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (fortsetzung: CheckedContinuation<String, Error>) in
                self.aufgabe.receive { ergebnis in
                    switch ergebnis {
                    case .failure(let fehler):
                        fortsetzung.resume(throwing: fehler)
                    case .success(.string(let text)):
                        fortsetzung.resume(returning: text)
                    case .success(.data(let daten)):
                        fortsetzung.resume(returning: String(decoding: daten, as: UTF8.self))
                    case .success:
                        fortsetzung.resume(throwing: WebSocketFehler.unbekannteNachricht)
                    }
                }
            }
        } onCancel: {
            // Abbruch der Beobachtung schließt die Verbindung, sonst wartet receive weiter.
            self.aufgabe.cancel(with: .goingAway, reason: nil)
        }
    }

    public func schliesse() {
        aufgabe.cancel(with: .normalClosure, reason: nil)
    }
}
