import Foundation
import StowCore

private let cliVersion = "0.1.0"

@main
@MainActor
struct StowCLI {
    static func main() {
        let renderer = StowCLIOutputRenderer()
        let wantsJSON = CommandLine.arguments.dropFirst().contains("--json")
        let output: StowCLIOutput
        do {
            var parser = StowCLIArguments(arguments: Array(CommandLine.arguments.dropFirst()))
            switch try parser.parse() {
            case .help:
                output = StowCLIOutput(standardOutput: StowCLIArguments.usage + "\n", standardError: "", exitCode: 0)
            case .version(let json):
                if json {
                    let object: [String: Any] = [
                        "schema_version": StowAutomationProtocol.schemaVersion,
                        "version": cliVersion,
                    ]
                    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                    output = StowCLIOutput(standardOutput: String(decoding: data, as: UTF8.self) + "\n", standardError: "", exitCode: 0)
                } else {
                    output = StowCLIOutput(standardOutput: "stow \(cliVersion)\n", standardError: "", exitCode: 0)
                }
            case .remote(let request, let json, let timeout, let exportOptions):
                let spool = try StowAutomationSpool(rootURL: StowSharedStorage.automationRootURL())
                let client = StowCLIClient(spool: spool)
                let response = client.copyExportIfRequested(
                    in: client.send(request, timeout: timeout),
                    options: exportOptions
                )
                output = renderer.render(response, json: json)
            }
        } catch {
            output = renderer.renderLocalError(error.localizedDescription, json: wantsJSON)
        }
        if !output.standardOutput.isEmpty {
            FileHandle.standardOutput.write(Data(output.standardOutput.utf8))
        }
        if !output.standardError.isEmpty {
            FileHandle.standardError.write(Data(output.standardError.utf8))
        }
        Foundation.exit(output.exitCode)
    }
}
