import ClawdLightCore
import Foundation
import TestKit

enum HTTPRequestParserSuite {

    private static func request(
        method: String = "POST",
        path: String = "/signal",
        headers: [String] = ["X-Claude-Entrypoint: claude-vscode"],
        body: String
    ) -> Data {
        let head = ([
            "\(method) \(path) HTTP/1.1",
            "Host: 127.0.0.1",
            "Content-Length: \(Data(body.utf8).count)",
        ] + headers).joined(separator: "\r\n")
        return Data((head + "\r\n\r\n" + body).utf8)
    }

    static let suite = TestSuite("HTTP request parsing", [

        TestCase("Decodes a complete POST") { t in
            let result = HTTPRequestParser.parse(request(body: #"{"a":1}"#))

            guard case .complete(let parsed, let consumed) = result else {
                return t.fail("expected .complete, got \(result)")
            }
            t.expectEqual(parsed.method, "POST", "method")
            t.expectEqual(parsed.path, "/signal", "path")
            t.expectEqual(String(data: parsed.body, encoding: .utf8), #"{"a":1}"#, "body")
            t.expectEqual(parsed.header("X-Claude-Entrypoint"), "claude-vscode", "custom header")
            t.expect(consumed > 0, "consumed bytes not computed")
        },

        TestCase("Header lookup ignores case") { t in
            let result = HTTPRequestParser.parse(request(body: "{}"))
            guard case .complete(let parsed, _) = result else {
                return t.fail("expected .complete")
            }
            t.expectEqual(parsed.header("x-claude-entrypoint"), "claude-vscode", "lowercase")
            t.expectEqual(parsed.header("X-CLAUDE-ENTRYPOINT"), "claude-vscode", "uppercase")
        },

        TestCase("Reports incomplete when the headers are missing") { t in
            let partial = Data("POST /signal HTTP/1.1\r\nHost: 127.0.0.1".utf8)
            t.expectEqual(HTTPRequestParser.parse(partial), .incomplete)
        },

        TestCase("Reports incomplete when the body arrived halfway") { t in
            let full = request(body: #"{"long":"abcdefghij"}"#)
            let truncated = full.prefix(full.count - 5)
            t.expectEqual(HTTPRequestParser.parse(Data(truncated)), .incomplete)
        },

        TestCase("Accepts a request with no body") { t in
            let data = Data("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
            guard case .complete(let parsed, _) = HTTPRequestParser.parse(data) else {
                return t.fail("expected .complete")
            }
            t.expectEqual(parsed.method, "GET", "method")
            t.expectEqual(parsed.path, "/health", "path")
            t.expectEqual(parsed.body.count, 0, "body")
        },

        TestCase("Rejects a malformed request line") { t in
            let data = Data("GARBAGE\r\nHost: x\r\n\r\n".utf8)
            guard case .malformed = HTTPRequestParser.parse(data) else {
                return t.fail("expected .malformed")
            }
        },

        TestCase("Rejects a Content-Length beyond the limit") { t in
            let head = [
                "POST /signal HTTP/1.1",
                "Content-Length: \(AppConfig.maxRequestBodyBytes + 1)",
            ].joined(separator: "\r\n")
            let data = Data((head + "\r\n\r\n").utf8)

            guard case .malformed = HTTPRequestParser.parse(data) else {
                return t.fail("expected .malformed")
            }
        },

        TestCase("Reports the consumed bytes for pipelining") { t in
            let first = request(body: "{}")
            let combined = first + Data("POST /signal HTTP/1.1\r\n".utf8)

            guard case .complete(_, let consumed) = HTTPRequestParser.parse(combined) else {
                return t.fail("expected .complete")
            }
            t.expectEqual(consumed, first.count, "must consume only the first request")
        },

        TestCase("The response is valid HTTP") { t in
            let response = HTTPRequestParser.response(status: 204, reason: "No Content")
            let text = String(data: response, encoding: .utf8) ?? ""

            t.expect(text.hasPrefix("HTTP/1.1 204 No Content\r\n"), "status line missing")
            t.expect(text.contains("Content-Length: 0"), "Content-Length missing")
            t.expect(text.hasSuffix("\r\n\r\n"), "missing the blank line closing the headers")
        },

        TestCase("A response with a body declares the right length") { t in
            let response = HTTPRequestParser.response(status: 400, reason: "Bad Request", body: "oops!!")
            let text = String(data: response, encoding: .utf8) ?? ""

            t.expect(text.contains("Content-Length: 6"), "wrong length in: \(text)")
            t.expect(text.hasSuffix("oops!!"), "body missing")
        },
    ])
}
