import XCTest
@testable import MenuStatus

final class ProviderConfigStoreTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.routes = [:]
        super.tearDown()
    }

    // MARK: - removeProvider cleanup

    @MainActor
    func testRemoveProviderClearsOrphanedPerProviderState() {
        let suiteName = "ProviderConfigStoreTests.removeOrphans"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("providers-\(UUID().uuidString).json")
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tmpFile)
        }

        let settings = SettingsStore(defaults: defaults)
        let configStore = ProviderConfigStore(fileURL: tmpFile)
        let custom = ProviderConfig(
            id: "custom-1",
            displayName: "Custom",
            baseURL: URL(string: "https://status.example.com")!,
            platform: .atlassianStatuspage,
            isBuiltIn: false
        )
        configStore.addProvider(custom)

        settings.customProviderNames[custom.id] = "My Alias"
        settings.mutedProviderIDs.insert(custom.id)
        settings.groupExpansionOverrides["\(custom.id):section-a"] = true
        settings.providerOrder = [custom.id]

        configStore.removeProvider(id: custom.id, settings: settings)

        // All per-provider state keyed by id must be gone, not just disabled/order.
        XCTAssertNil(settings.customProviderNames[custom.id])
        XCTAssertFalse(settings.mutedProviderIDs.contains(custom.id))
        XCTAssertNil(settings.groupExpansionOverrides["\(custom.id):section-a"])
        XCTAssertFalse(settings.providerOrder.contains(custom.id))
        XCTAssertNil(configStore.provider(for: custom.id))
    }

    // MARK: - detectPlatform

    func testDetectPlatformReturnsAtlassianForPlainHTML() async throws {
        let html = "<html><body><div data-component-id=\"test\">Hello</div></body></html>"
        let session = makeMockSession(routes: [
            .root: .ok(html)
        ])

        let platform = try await ProviderConfigStore.detectPlatform(
            url: URL(string: "https://example.statuspage.io")!,
            session: session
        )
        XCTAssertEqual(platform, .atlassianStatuspage)
    }

    func testDetectPlatformReturnsIncidentIOForNextPushBlocks() async throws {
        let html = """
        <html><body>
        <script>self.__next_f.push([1,"{\\"page\\":\\"test\\"}"])</script>
        </body></html>
        """
        let session = makeMockSession(routes: [
            .root: .ok(html)
        ])

        let platform = try await ProviderConfigStore.detectPlatform(
            url: URL(string: "https://status.openai.com")!,
            session: session
        )
        XCTAssertEqual(platform, .incidentIO)
    }

    func testDetectPlatformReturnsFlashdutyForEmbeddedPageConfig() async throws {
        let html = """
        <html><body>
        <script>self.__next_f.push([1,"8:[\\"$\\",\\"$L1a\\",null,{\\"initialPageConfig\\":{\\"page_id\\":6410630422455,\\"name\\":\\"DeepSeek\\",\\"custom_domain\\":\\"status.deepseek.com\\",\\"components\\":[]}}]"])</script>
        </body></html>
        """
        let session = makeMockSession(routes: [
            .root: .ok(html)
        ])

        let platform = try await ProviderConfigStore.detectPlatform(
            url: URL(string: "https://status.deepseek.com")!,
            session: session
        )
        XCTAssertEqual(platform, .flashduty)
    }

    func testDetectPlatformDefaultsToAtlassianForNonUTF8Data() async throws {
        let session = makeMockSession(routes: [
            .root: .okData(Data([0xFF, 0xFE]))
        ])

        let platform = try await ProviderConfigStore.detectPlatform(
            url: URL(string: "https://example.statuspage.io")!,
            session: session
        )
        XCTAssertEqual(platform, .atlassianStatuspage)
    }

    func testDetectPlatformThrowsOnHTTPError() async {
        let session = makeMockSession(routes: [
            .root: .error(503)
        ])

        do {
            _ = try await ProviderConfigStore.detectPlatform(
                url: URL(string: "https://example.statuspage.io")!,
                session: session
            )
            XCTFail("Expected error")
        } catch {
            guard let transportError = error as? StatusClientTransportError else {
                XCTFail("Expected StatusClientTransportError, got \(error)")
                return
            }
            if case .unsuccessfulStatusCode(_, let code) = transportError {
                XCTAssertEqual(code, 503)
            } else {
                XCTFail("Expected unsuccessfulStatusCode, got \(transportError)")
            }
        }
    }

    // MARK: - detect (end-to-end)

    func testDetectAtlassianProviderFromSummaryAndHTML() async throws {
        let summaryJSON = """
        {
            "page": {"id": "1password", "name": "1Password", "url": "https://status.1password.com", "time_zone": "Etc/UTC"},
            "status": {"indicator": "none", "description": "All Systems Operational"},
            "components": [{"id": "api", "name": "API", "status": "operational"}]
        }
        """
        let html = "<html><body><div data-component-id=\"api\">API</div></body></html>"
        let session = makeMockSession(routes: [
            .summary: .ok(summaryJSON),
            .root: .ok(html)
        ])

        let config = try await ProviderConfigStore.detect(
            url: URL(string: "https://status.1password.com")!,
            session: session
        )

        XCTAssertEqual(config.id, "1password")
        XCTAssertEqual(config.displayName, "1Password")
        XCTAssertEqual(config.platform, .atlassianStatuspage)
        XCTAssertFalse(config.isBuiltIn)
        XCTAssertEqual(config.baseURL, URL(string: "https://status.1password.com")!)
    }

    func testDetectIncidentIOProviderFromSummaryAndHTML() async throws {
        let summaryJSON = """
        {
            "page": {"id": "openai", "name": "OpenAI", "url": "https://status.openai.com", "time_zone": "America/Los_Angeles"},
            "status": {"indicator": "none", "description": "Operational"},
            "components": [{"id": "chatgpt", "name": "ChatGPT", "status": "operational"}]
        }
        """
        let html = """
        <html><body>
        <script>self.__next_f.push([1,"{\\"page\\":\\"openai\\"}"])</script>
        </body></html>
        """
        let session = makeMockSession(routes: [
            .summary: .ok(summaryJSON),
            .root: .ok(html)
        ])

        let config = try await ProviderConfigStore.detect(
            url: URL(string: "https://status.openai.com")!,
            session: session
        )

        XCTAssertEqual(config.id, "openai")
        XCTAssertEqual(config.displayName, "OpenAI")
        XCTAssertEqual(config.platform, .incidentIO)
        XCTAssertFalse(config.isBuiltIn)
    }

    func testDetectFlashdutyProviderFromHTMLWhenSummaryAPIIsMissing() async throws {
        let html = """
        <html><body>
        <script>self.__next_f.push([1,"8:[\\"$\\",\\"$L1a\\",null,{\\"initialPageConfig\\":{\\"page_id\\":6410630422455,\\"name\\":\\"DeepSeek\\",\\"custom_domain\\":\\"status.deepseek.com\\",\\"components\\":[{\\"component_id\\":\\"api\\",\\"name\\":\\"API Service\\",\\"description\\":\\"API status\\",\\"available_since_seconds\\":1706745600,\\"order_id\\":1}],\\"sections\\":[]}}]"])</script>
        </body></html>
        """
        let session = makeMockSession(routes: [
            .summary: .error(404),
            .root: .ok(html)
        ])

        let config = try await ProviderConfigStore.detect(
            url: URL(string: "https://status.deepseek.com")!,
            session: session
        )

        XCTAssertEqual(config.id, "6410630422455")
        XCTAssertEqual(config.displayName, "DeepSeek")
        XCTAssertEqual(config.platform, .flashduty)
        XCTAssertFalse(config.isBuiltIn)
    }

    func testDetectThrowsOnSummaryHTTPError() async {
        let session = makeMockSession(routes: [
            .summary: .error(404)
        ])

        do {
            _ = try await ProviderConfigStore.detect(
                url: URL(string: "https://status.example.com")!,
                session: session
            )
            XCTFail("Expected error")
        } catch let error as StatusClientTransportError {
            if case .unsuccessfulStatusCode(_, let code) = error {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Expected unsuccessfulStatusCode, got \(error)")
            }
        } catch {
            XCTFail("Expected StatusClientTransportError, got \(error)")
        }
    }

    func testDetectThrowsOnInvalidSummaryJSON() async {
        let session = makeMockSession(routes: [
            .summary: .ok("not json")
        ])

        do {
            _ = try await ProviderConfigStore.detect(
                url: URL(string: "https://status.example.com")!,
                session: session
            )
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is DecodingError, "Expected DecodingError, got \(error)")
        }
    }

    // MARK: - Helpers

    private enum Route: Hashable {
        case summary
        case root
    }

    private enum Response {
        case ok(String)
        case okData(Data)
        case error(Int)
    }

    private final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var routes: [Route: Response] = [:]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            let route: Route = url.lastPathComponent == "summary.json" ? .summary : .root
            guard let response = MockURLProtocol.routes[route] else {
                client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
                return
            }

            switch response {
            case .ok(let body):
                let data = Data(body.utf8)
                let httpResponse = HTTPURLResponse(
                    url: url, statusCode: 200,
                    httpVersion: "HTTP/1.1", headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)

            case .okData(let data):
                let httpResponse = HTTPURLResponse(
                    url: url, statusCode: 200,
                    httpVersion: "HTTP/1.1", headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)

            case .error(let statusCode):
                let httpResponse = HTTPURLResponse(
                    url: url, statusCode: statusCode,
                    httpVersion: "HTTP/1.1", headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    private func makeMockSession(routes: [Route: Response]) -> URLSession {
        MockURLProtocol.routes = routes
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
