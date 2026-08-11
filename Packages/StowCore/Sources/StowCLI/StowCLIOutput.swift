import Foundation
import StowCore

struct StowCLIOutput {
    var standardOutput: String
    var standardError: String
    var exitCode: Int32
}

struct StowCLIOutputRenderer {
    func render(_ response: StowAutomationResponse, json: Bool) -> StowCLIOutput {
        if json {
            do {
                let data = try StowAutomationProtocol.encoder().encode(response)
                return StowCLIOutput(
                    standardOutput: String(decoding: data, as: UTF8.self) + "\n",
                    standardError: "",
                    exitCode: exitCode(for: response.error)
                )
            } catch {
                return StowCLIOutput(standardOutput: "", standardError: "Unable to encode JSON output.\n", exitCode: 70)
            }
        }
        if let error = response.error {
            let fallback = error.fallbackPath.map { "fallback-path: \($0)\n" } ?? ""
            return StowCLIOutput(
                standardOutput: "",
                standardError: "stow: \(error.message)\nrequest-id: \(response.requestID.uuidString)\n\(fallback)",
                exitCode: exitCode(for: error)
            )
        }
        guard let result = response.data else {
            return StowCLIOutput(standardOutput: "", standardError: "stow: Empty response.\n", exitCode: 70)
        }
        if let status = result.status {
            return success("Stow \(status.hostVersion) is ready (\(status.storage)).\n")
        }
        if let items = result.items {
            let lines = items.map {
                [
                    $0.id.uuidString,
                    $0.type.rawValue,
                    $0.status.rawValue,
                    $0.title.replacingOccurrences(of: "\t", with: " "),
                    $0.snippet?.replacingOccurrences(of: "\t", with: " ") ?? "",
                ].joined(separator: "\t")
            }
            return success(lines.isEmpty ? "No items found.\n" : lines.joined(separator: "\n") + "\n")
        }
        if let item = result.item {
            var lines = [
                "id: \(item.id.uuidString)",
                "type: \(item.type.rawValue)",
                "status: \(item.status.rawValue)",
                "title: \(item.title)",
            ]
            if let url = item.urlString { lines.append("url: \(url)") }
            if let language = item.language { lines.append("language: \(language)") }
            if let note = item.note { lines.append("note: \(note)") }
            if let text = item.textContent { lines += ["", text] }
            if !item.attachments.isEmpty {
                lines.append("")
                lines += item.attachments.map {
                    "attachment: \($0.id.uuidString) \($0.contentType) \($0.byteCount) \($0.fileName)"
                }
            }
            return success(lines.joined(separator: "\n") + "\n")
        }
        if let exported = result.export {
            return success(exported.path + "\n")
        }
        return success("OK\n")
    }

    func renderLocalError(_ message: String, json: Bool, requestID: UUID = UUID()) -> StowCLIOutput {
        if json {
            return render(
                StowAutomationResponse(
                    requestID: requestID,
                    error: StowAutomationError(code: .invalidRequest, message: message)
                ),
                json: true
            )
        }
        return StowCLIOutput(standardOutput: "", standardError: "stow: \(message)\n\n\(StowCLIArguments.usage)\n", exitCode: 64)
    }

    private func success(_ output: String) -> StowCLIOutput {
        StowCLIOutput(standardOutput: output, standardError: "", exitCode: 0)
    }

    private func exitCode(for error: StowAutomationError?) -> Int32 {
        guard let error else { return 0 }
        return switch error.code {
        case .invalidRequest: 64
        case .validationFailed: 65
        case .itemNotFound, .attachmentNotFound, .attachmentSelectionRequired: 66
        case .hostUnavailable: 69
        case .internalFailure, .unsupportedVersion: 70
        case .ioFailure: 74
        case .timeout: 75
        }
    }
}
