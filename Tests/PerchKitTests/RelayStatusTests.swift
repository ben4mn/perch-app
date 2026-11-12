import XCTest
@testable import PerchKit

/// A Relay that answers /api/presence with a set status, and remembers the token it was sent.
final class StubRelay: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var failure: URLError?
    nonisolated(unsafe) static var lastAuthorization: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        if let failure = Self.failure { return client!.urlProtocol(self, didFailWithError: failure) }
        let body = """
        {"agents": [
          {"name": "claude", "status": "Here", "isActive": true, "updated": "2026-11-10T18:14:05.000Z"},
          {"name": "dot", "status": "Away", "isActive": false, "updated": "2026-11-10T17:14:05.000Z"}
        ], "recent": []}
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Settings says whether Perch is connected to the Relay, and if not, why.
final class RelayStatusTests: XCTestCase {
    private func client(token: String) -> RelayClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubRelay.self]
        return RelayClient(baseURL: URL(string: "http://127.0.0.1:8787")!, token: token, session: URLSession(configuration: configuration))
    }

    override func setUp() {
        StubRelay.status = 200
        StubRelay.failure = nil
        StubRelay.lastAuthorization = nil
    }

    func testAPastedTokenLosesItsLineBreak() async throws {
        // `cat token | pbcopy` copies the file's last line break too, and the Relay refuses a token with one.
        _ = try await client(token: "  perch_abc123\n").presence()
        XCTAssertEqual(StubRelay.lastAuthorization, "Bearer perch_abc123")
    }

    func testConnectedSaysHowManyAgentsAreWorking() async throws {
        let presence = try await client(token: "t").presence()
        let status = RelayStatus.connected(agentsHere: presence.agents.filter(\.isActive).count)
        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.title, "Connected")
        XCTAssertEqual(status.detail, "1 agent is working now.")
        XCTAssertEqual(RelayStatus.connected(agentsHere: 0).detail, "No agents are working right now.")
        XCTAssertEqual(RelayStatus.connected(agentsHere: 3).detail, "3 agents are working now.")
    }

    func testARefusedTokenSaysSo() async {
        StubRelay.status = 401
        do {
            _ = try await client(token: "wrong").presence()
            XCTFail("expected the Relay to refuse")
        } catch {
            let status = RelayStatus(error: error)
            XCTAssertEqual(status, .refused)
            XCTAssertFalse(status.isConnected)
            XCTAssertEqual(status.title, "Token refused")
        }
    }

    func testNothingAnsweringSaysTheRelayCantBeReached() async {
        StubRelay.failure = URLError(.cannotConnectToHost)
        do {
            _ = try await client(token: "t").presence()
            XCTFail("expected no answer")
        } catch {
            XCTAssertEqual(RelayStatus(error: error), .unreachable)
            XCTAssertEqual(RelayStatus(error: error).title, "Can't reach the Relay")
        }
    }

    func testAnyOtherErrorShowsItsCode() async {
        StubRelay.status = 500
        do {
            _ = try await client(token: "t").presence()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(RelayStatus(error: error), .failed("HTTP 500"))
            XCTAssertEqual(RelayStatus(error: error).detail, "The Relay answered with an error (HTTP 500).")
        }
    }

    func testBeforeConnectingItSaysWhatToDo() {
        XCTAssertEqual(RelayStatus.off.title, "Not connected")
        XCTAssertEqual(RelayStatus.connecting.title, "Connecting")
        XCTAssertFalse(RelayStatus.connecting.isConnected)
    }
}
