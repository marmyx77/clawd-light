import Foundation

/// An HTTP request pared down to the bone.
public struct HTTPRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// Case-insensitive header lookup, as the RFC requires.
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// The header under its current name, or under the one it used to have.
    ///
    /// Renaming a header is renaming a contract with senders this process cannot
    /// reach: a hook script installed on a node behind ssh keeps sending the old
    /// name until somebody reinstalls it there. Reading both is what makes the
    /// rename a release rather than an outage, and the fallback is deliberately
    /// read-only — nothing in this project emits a legacy name — so the day every
    /// sender has been reinstalled, this argument disappears and nothing else
    /// has to change.
    public func header(_ name: String, orLegacy legacy: String) -> String? {
        header(name) ?? header(legacy)
    }
}

/// Outcome of a parse attempt on a buffer that may still be incomplete.
public enum HTTPParseResult: Sendable, Equatable {
    /// More bytes are needed before a decision can be made.
    case incomplete
    /// A complete request, plus any bytes of the next one already read.
    case complete(HTTPRequest, consumedBytes: Int)
    /// Malformed request: the connection must be closed.
    case malformed(String)
}

/// A minimal HTTP/1.1 parser, sufficient to receive the hooks' POSTs.
///
/// Deliberately not a general-purpose HTTP server: it accepts only what the hook
/// script sends. Everything else is rejected rather than interpreted.
public enum HTTPRequestParser {

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    public static func parse(_ buffer: Data) -> HTTPParseResult {
        guard buffer.count <= AppConfig.maxRequestBodyBytes * 2 else {
            return .malformed("request too large")
        }

        guard let terminatorRange = buffer.range(of: headerTerminator) else {
            return .incomplete
        }

        let headerData = buffer[buffer.startIndex..<terminatorRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .malformed("headers not decodable as UTF-8")
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            return .malformed("empty request")
        }

        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else {
            return .malformed("malformed request line")
        }

        let method = String(requestLine[0]).uppercased()
        let path = String(requestLine[1])
        let headers = parseHeaders(lines)

        let declaredLength = headers["content-length"].flatMap(Int.init) ?? 0
        guard declaredLength >= 0, declaredLength <= AppConfig.maxRequestBodyBytes else {
            return .malformed("Content-Length out of bounds")
        }

        let bodyStart = terminatorRange.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard available >= declaredLength else {
            return .incomplete
        }

        let bodyEnd = buffer.index(bodyStart, offsetBy: declaredLength)
        let request = HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: Data(buffer[bodyStart..<bodyEnd])
        )
        let consumed = buffer.distance(from: buffer.startIndex, to: bodyEnd)
        return .complete(request, consumedBytes: consumed)
    }

    /// Builds a complete HTTP response with a textual body.
    public static func response(
        status: Int,
        reason: String,
        body: String = "",
        contentType: String = "text/plain; charset=utf-8"
    ) -> Data {
        response(status: status, reason: reason, body: Data(body.utf8), contentType: contentType)
    }

    /// Builds a complete HTTP response with a binary body.
    public static func response(
        status: Int,
        reason: String,
        body: Data,
        contentType: String
    ) -> Data {
        let head = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Length: \(body.count)\r
        Content-Type: \(contentType)\r
        Connection: close\r
        \r

        """
        return Data(head.utf8) + body
    }

    // MARK: - Helpers

    private static func parseHeaders(_ lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<separator]).trimmed.lowercased()
            let value = String(line[line.index(after: separator)...]).trimmed
            guard !name.isEmpty else { continue }
            headers[name] = value
        }
        return headers
    }
}
