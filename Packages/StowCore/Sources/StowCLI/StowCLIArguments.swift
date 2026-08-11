import Foundation
import StowCore

struct StowCLIParseError: Error, Equatable, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct StowCLIExportOptions: Equatable {
    var outputPath: String?
    var force: Bool
}

enum StowCLIInvocation: Equatable {
    case help
    case version(json: Bool)
    case remote(request: StowAutomationRequest, json: Bool, timeout: TimeInterval, export: StowCLIExportOptions?)
}

struct StowCLIArguments {
    static let usage = """
    Usage:
      stow status [--json] [--timeout SECONDS]
      stow search [QUERY] [--status inbox|archived|trashed|all] [--type TYPE] [--limit N] [--json]
      stow get ITEM_ID [--json]
      stow add --type text|code|link [--title TITLE] [--language LANGUAGE] [--note NOTE] [--url URL] [--text TEXT|--stdin] [--request-id UUID] [--json]
      stow export ITEM_ID [--attachment ATTACHMENT_ID] [--output PATH] [--force] [--json]
      stow help
      stow version [--json]
    """

    private var arguments: [String]
    private var readStandardInput: () throws -> String

    init(arguments: [String], readStandardInput: @escaping () throws -> String = StowCLIArguments.readStdin) {
        self.arguments = arguments
        self.readStandardInput = readStandardInput
    }

    mutating func parse() throws -> StowCLIInvocation {
        guard let command = arguments.first else { return .help }
        arguments.removeFirst()
        if command == "help" || command == "--help" || command == "-h" { return .help }
        if command == "version" || command == "--version" {
            let json = consumeFlag("--json")
            try requireNoArguments()
            return .version(json: json)
        }
        switch command {
        case "status": return try parseStatus()
        case "search": return try parseSearch()
        case "get": return try parseGet()
        case "add": return try parseAdd()
        case "export": return try parseExport()
        default: throw StowCLIParseError(message: "Unknown command: \(command)")
        }
    }

    private mutating func parseStatus() throws -> StowCLIInvocation {
        var common = CommonOptions()
        while let option = arguments.first {
            arguments.removeFirst()
            guard option.hasPrefix("-"), try common.consume(option, from: &arguments) else {
                throw StowCLIParseError(message: "Unknown option: \(option)")
            }
        }
        return .remote(
            request: StowAutomationRequest(command: .status),
            json: common.json,
            timeout: common.timeout,
            export: nil
        )
    }

    private mutating func parseSearch() throws -> StowCLIInvocation {
        var common = CommonOptions()
        var status: StowAutomationStatusFilter?
        var type: ItemType?
        var limit = 20
        var queryParts: [String] = []
        while let argument = arguments.first {
            arguments.removeFirst()
            if argument.hasPrefix("-") {
                if try common.consume(argument, from: &arguments) { continue }
                switch argument {
                case "--status": status = try parseStatusFilter(requireValue(after: argument))
                case "--type": type = try parseItemType(requireValue(after: argument))
                case "--limit": limit = try parseLimit(requireValue(after: argument))
                default: throw StowCLIParseError(message: "Unknown option: \(argument)")
                }
            } else {
                queryParts.append(argument)
            }
        }
        let query = queryParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return .remote(
            request: StowAutomationRequest(command: .search, search: .init(query: query, status: status, type: type, limit: limit)),
            json: common.json,
            timeout: common.timeout,
            export: nil
        )
    }

    private mutating func parseGet() throws -> StowCLIInvocation {
        let itemID = try parseLeadingUUID(named: "ITEM_ID")
        var common = CommonOptions()
        while let option = arguments.first {
            arguments.removeFirst()
            guard option.hasPrefix("-"), try common.consume(option, from: &arguments) else {
                throw StowCLIParseError(message: "Unknown option: \(option)")
            }
        }
        return .remote(
            request: StowAutomationRequest(command: .get, get: .init(itemID: itemID)),
            json: common.json,
            timeout: common.timeout,
            export: nil
        )
    }

    private mutating func parseAdd() throws -> StowCLIInvocation {
        var common = CommonOptions()
        var type: ItemType?
        var title = ""
        var language: String?
        var note: String?
        var url: String?
        var text: String?
        var usesStdin = false
        var requestID = UUID()
        while let option = arguments.first {
            arguments.removeFirst()
            guard option.hasPrefix("-") else { throw StowCLIParseError(message: "Unexpected argument: \(option)") }
            if try common.consume(option, from: &arguments) { continue }
            switch option {
            case "--type": type = try parseItemType(requireValue(after: option))
            case "--title": title = try requireValue(after: option)
            case "--language": language = try requireValue(after: option)
            case "--note": note = try requireValue(after: option)
            case "--url": url = try requireValue(after: option)
            case "--text": text = try requireValue(after: option)
            case "--stdin": usesStdin = true
            case "--request-id":
                let value = try requireValue(after: option)
                guard let id = UUID(uuidString: value) else { throw StowCLIParseError(message: "Invalid request ID: \(value)") }
                requestID = id
            default: throw StowCLIParseError(message: "Unknown option: \(option)")
            }
        }
        guard let type else { throw StowCLIParseError(message: "add requires --type text, code, or link.") }
        guard [.text, .code, .link].contains(type) else {
            throw StowCLIParseError(message: "add supports only text, code, and link in this version.")
        }
        guard !(usesStdin && text != nil) else { throw StowCLIParseError(message: "Use either --text or --stdin, not both.") }
        if usesStdin { text = try readStandardInput() }
        if type == .link, url == nil { throw StowCLIParseError(message: "A link requires --url.") }
        if (type == .text || type == .code), text == nil { throw StowCLIParseError(message: "Text and code require --text or --stdin.") }
        let draft = CaptureDraft(
            id: requestID,
            type: type,
            title: title,
            textContent: type == .link ? nil : text,
            urlString: type == .link ? url : nil,
            sourceApp: "Stow CLI",
            note: note,
            language: language
        )
        return .remote(
            request: StowAutomationRequest(requestID: requestID, command: .add, add: .init(draft: draft)),
            json: common.json,
            timeout: common.timeout,
            export: nil
        )
    }

    private mutating func parseExport() throws -> StowCLIInvocation {
        let itemID = try parseLeadingUUID(named: "ITEM_ID")
        var common = CommonOptions()
        var attachmentID: UUID?
        var outputPath: String?
        var force = false
        while let option = arguments.first {
            arguments.removeFirst()
            guard option.hasPrefix("-") else { throw StowCLIParseError(message: "Unexpected argument: \(option)") }
            if try common.consume(option, from: &arguments) { continue }
            switch option {
            case "--attachment":
                let value = try requireValue(after: option)
                guard let id = UUID(uuidString: value) else { throw StowCLIParseError(message: "Invalid attachment ID: \(value)") }
                attachmentID = id
            case "--output": outputPath = try requireValue(after: option)
            case "--force": force = true
            default: throw StowCLIParseError(message: "Unknown option: \(option)")
            }
        }
        return .remote(
            request: StowAutomationRequest(command: .export, export: .init(itemID: itemID, attachmentID: attachmentID)),
            json: common.json,
            timeout: common.timeout,
            export: StowCLIExportOptions(outputPath: outputPath, force: force)
        )
    }

    private mutating func parseLeadingUUID(named name: String) throws -> UUID {
        guard let value = arguments.first, !value.hasPrefix("-") else {
            throw StowCLIParseError(message: "The command requires \(name).")
        }
        arguments.removeFirst()
        guard let id = UUID(uuidString: value) else { throw StowCLIParseError(message: "Invalid \(name): \(value)") }
        return id
    }

    private mutating func requireValue(after option: String) throws -> String {
        guard let value = arguments.first, !value.hasPrefix("--") else {
            throw StowCLIParseError(message: "\(option) requires a value.")
        }
        arguments.removeFirst()
        return value
    }

    private func parseStatusFilter(_ value: String) throws -> StowAutomationStatusFilter {
        guard let status = StowAutomationStatusFilter(rawValue: value.lowercased()) else {
            throw StowCLIParseError(message: "Invalid status: \(value)")
        }
        return status
    }

    private func parseItemType(_ value: String) throws -> ItemType {
        guard let type = ItemType(rawValue: value.lowercased()) else {
            throw StowCLIParseError(message: "Invalid item type: \(value)")
        }
        return type
    }

    private func parseLimit(_ value: String) throws -> Int {
        guard let limit = Int(value), (1...10_000).contains(limit) else {
            throw StowCLIParseError(message: "Limit must be between 1 and 10000.")
        }
        return limit
    }

    private mutating func consumeFlag(_ flag: String) -> Bool {
        guard let index = arguments.firstIndex(of: flag) else { return false }
        arguments.remove(at: index)
        return true
    }

    private func requireNoArguments() throws {
        guard arguments.isEmpty else { throw StowCLIParseError(message: "Unexpected argument: \(arguments[0])") }
    }

    private static func readStdin() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8) else {
            throw StowCLIParseError(message: "Standard input is not valid UTF-8.")
        }
        return value
    }
}

private struct CommonOptions {
    var json = false
    var timeout: TimeInterval = 10

    mutating func consume(_ option: String, from arguments: inout [String]) throws -> Bool {
        switch option {
        case "--json": json = true; return true
        case "--timeout":
            guard let value = arguments.first, let seconds = TimeInterval(value), seconds > 0 else {
                throw StowCLIParseError(message: "--timeout requires a positive number of seconds.")
            }
            arguments.removeFirst()
            timeout = seconds
            return true
        default: return false
        }
    }
}
