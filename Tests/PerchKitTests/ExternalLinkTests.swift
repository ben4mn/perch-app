import XCTest
@testable import PerchKit

/// What Perch hands to the system to open. A note is text anyone can write, and the reader's web view meets
/// every address in it: only a web page or an email address goes to the browser or Mail. A `tel:` link the
/// page failed to stop once made macOS offer to place a call.
final class ExternalLinkTests: XCTestCase {
    private func opens(_ address: String) throws -> Bool {
        ExternalLink.opens(try XCTUnwrap(URL(string: address), address))
    }

    func testWebPagesAndEmailAddressesOpen() throws {
        for address in ["https://example.com/page?q=1#top", "http://www.example.com", "mailto:alex@example.com"] {
            XCTAssertTrue(try opens(address), address)
        }
    }

    func testTheSchemeMayBeWrittenInAnyCase() throws {
        for address in ["HTTPS://example.com", "Http://example.com", "MailTo:alex@example.com", "hTtPs://example.com"] {
            XCTAssertTrue(try opens(address), address)
        }
    }

    func testNothingElseOpens() throws {
        let refused = [
            "tel:+15550100", "TEL:+15550100", "sms:+15550100", "facetime:alex@example.com",
            "file:///etc/passwd", "FILE:///etc/passwd",
            "javascript:window.__xss=1", "JaVaScRiPt:alert(1)",
            // The app's own pages and the notebook's files, which the reader serves to itself.
            "perch-app://app/whiteboard.html", "perch-vault://vault/xss.md", "perch://task/t1",
            // Some other app's scheme, real or made up.
            "x-evil://run", "claude://code/new?q=delete", "data:text/html,hi", "blob:perch-app://app/x", "about:blank",
            // Schemes that only start like the allowed ones.
            "https-evil://example.com", "mailto2:alex@example.com", "httpx://example.com",
        ]
        for address in refused { XCTAssertFalse(try opens(address), address) }
    }

    func testAnAddressWithNoSchemeDoesNotOpen() throws {
        for address in ["example.com", "//example.com/page", "/etc/passwd", "note.md", "#heading", ""] {
            guard let url = URL(string: address) else { continue }
            XCTAssertNil(url.scheme, address)
            XCTAssertFalse(ExternalLink.opens(url), address)
        }
    }
}
