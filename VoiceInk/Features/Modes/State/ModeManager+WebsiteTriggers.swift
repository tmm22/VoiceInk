import Foundation

extension ModeManager {
    /// Host, port and path of the active tab. The host is lowercased and loses a
    /// leading "www.". Triggers are stored without a scheme, so a bare host is
    /// parsed as one.
    static func target(ofBrowserURL url: String) -> (host: String, port: Int?, path: String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let absolute = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: absolute),
            let host = components.host,
            !host.isEmpty
        else {
            return nil
        }

        return (normalizedHost(host), components.port, components.path)
    }

    /// A trigger matches the host itself or any subdomain of it. A trigger that
    /// carries a path, such as "icloud.com/mail", also has to match that path
    /// prefix on a segment boundary. Triggers are stored lowercased, so paths
    /// are compared without regard to case.
    static func trigger(_ trigger: String, matches target: (host: String, port: Int?, path: String)) -> Bool {
        let parts = trigger.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return false }

        let authority = String(first)
        let triggerHost = normalizedHost(authority)
        guard !triggerHost.isEmpty else { return false }
        guard target.host == triggerHost || target.host.hasSuffix("." + triggerHost) else { return false }

        // A trigger that names a port only matches that port. A trigger whose
        // port is not a number matches nothing rather than every port.
        switch port(ofAuthority: authority) {
        case .absent: break
        case .malformed: return false
        case .number(let triggerPort): if target.port != triggerPort { return false }
        }

        guard parts.count > 1 else { return true }
        // URLComponents reports a decoded path, so decode the trigger as well.
        let rawTriggerPath = String(parts[1])
        let triggerPath = (rawTriggerPath.removingPercentEncoding ?? rawTriggerPath)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !triggerPath.isEmpty else { return true }

        let prefix = "/" + triggerPath
        let path = target.path.lowercased()
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    private enum TriggerPort {
        case absent
        case number(Int)
        case malformed
    }

    /// The port of a stored trigger. An IPv6 literal without a bracketed port
    /// carries colons of its own and counts as portless.
    private static func port(ofAuthority authority: String) -> TriggerPort {
        let suffix: Substring
        if authority.hasPrefix("[") {
            guard let closingBracket = authority.firstIndex(of: "]") else { return .malformed }
            let rest = authority[authority.index(after: closingBracket)...]
            guard rest.hasPrefix(":") else { return rest.isEmpty ? .absent : .malformed }
            suffix = rest.dropFirst()
        } else {
            guard authority.filter({ $0 == ":" }).count == 1,
                let portSeparator = authority.firstIndex(of: ":")
            else {
                return .absent
            }
            suffix = authority[authority.index(after: portSeparator)...]
        }

        guard let value = Int(suffix), (1...65535).contains(value) else { return .malformed }
        return .number(value)
    }

    /// Lowercases a host, drops a leading "www." and drops a port. An IPv6
    /// literal keeps its address: only a single colon is read as a port
    /// separator, and a bracketed literal is unwrapped first.
    private static func normalizedHost(_ host: String) -> String {
        var value = host.lowercased()
        if value.hasPrefix("["), let closingBracket = value.firstIndex(of: "]") {
            value = String(value[value.index(after: value.startIndex)..<closingBracket])
        } else if value.filter({ $0 == ":" }).count == 1, let portSeparator = value.firstIndex(of: ":") {
            value = String(value[..<portSeparator])
        }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }
        return value
    }
}
