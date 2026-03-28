import XCTest
@testable import MenuStatus

final class StatusClientTests: XCTestCase {
    func testValidateHTTPResponseAcceptsSuccessfulStatusCode() throws {
        let url = try XCTUnwrap(URL(string: "https://status.openai.com"))
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        )

        XCTAssertNoThrow(try StatusClient.validateHTTPResponse(response, for: url))
    }

    func testValidateHTTPResponseRejectsNonHTTPResponse() throws {
        let url = try XCTUnwrap(URL(string: "https://status.openai.com"))
        let response = URLResponse(
            url: url,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        XCTAssertThrowsError(try StatusClient.validateHTTPResponse(response, for: url)) { error in
            XCTAssertEqual(error as? StatusClientTransportError, .invalidResponse(url))
        }
    }

    func testValidateHTTPResponseRejectsUnsuccessfulStatusCode() throws {
        let url = try XCTUnwrap(URL(string: "https://status.claude.com"))
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)
        )

        XCTAssertThrowsError(try StatusClient.validateHTTPResponse(response, for: url)) { error in
            XCTAssertEqual(
                error as? StatusClientTransportError,
                .unsuccessfulStatusCode(url: url, statusCode: 503)
            )
        }
    }
}
