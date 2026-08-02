import XCTest
@testable import StowCore

final class CaptureRepresentationSelectorTests: XCTestCase {
    func testWebURLWinsOverTextAcrossMultipleProviders() {
        let providers = [
            CaptureProviderDescriptor(typeIdentifiers: ["public.plain-text"]),
            CaptureProviderDescriptor(typeIdentifiers: ["public.url"]),
        ]

        XCTAssertEqual(CaptureRepresentationSelector.select(providers), CaptureRepresentationSelection(providerIndex: 1, kind: .url))
    }

    func testImageWinsOverGenericDataAndNamedTextFileRemainsFile() {
        XCTAssertEqual(
            CaptureRepresentationSelector.select([CaptureProviderDescriptor(typeIdentifiers: ["public.data", "public.png"], suggestedName: "photo.png")]),
            CaptureRepresentationSelection(providerIndex: 0, kind: .image)
        )
        XCTAssertEqual(
            CaptureRepresentationSelector.select([CaptureProviderDescriptor(typeIdentifiers: ["public.plain-text", "public.data"], suggestedName: "main.swift")]),
            CaptureRepresentationSelection(providerIndex: 0, kind: .file)
        )
    }

    func testUnsupportedRepresentationsReturnNil() {
        XCTAssertTrue(CaptureValidationError.unsupportedRepresentation.localizedDescription.contains("URLs, text, images, and files"))
        XCTAssertNil(CaptureRepresentationSelector.select([CaptureProviderDescriptor(typeIdentifiers: ["com.example.unknown"])]))
    }
}
