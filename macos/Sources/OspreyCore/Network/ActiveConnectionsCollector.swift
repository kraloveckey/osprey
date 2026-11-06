import AppKit
import Foundation

/// Active network sockets and connections collector (Little Snitch / Activity Monitor style).
public struct NetworkConnection: Identifiable, Sendable, Equatable {
    public let id: String
    public let pid: Int32
    public let processName: String
    public let proto: String
    public let localEndpoint: String
    public let remoteEndpoint: String
    public let state: String
    public let isEstablished: Bool

    public init(
        id: String,
        pid: Int32,
        processName: String,
        proto: String,
        localEndpoint: String,
        remoteEndpoint: String,
        state: String,
        isEstablished: Bool
    ) {
        self.id = id
        self.pid = pid
        self.processName = processName
        self.proto = proto
        self.localEndpoint = localEndpoint
        self.remoteEndpoint = remoteEndpoint
        self.state = state
        self.isEstablished = isEstablished
    }
}

@MainActor
public final class ActiveConnectionsCollector: ObservableObject {
    @Published public var connections: [NetworkConnection] = []
    @Published public var isLoading: Bool = false
    @Published public var searchText: String = ""
    @Published public var selectedFilter: ConnectionFilter = .all
    @Published public var refreshInterval: RefreshInterval = .manual {
        didSet {
            restartTimer()
        }
    }
    @Published public var isAutoRefreshing: Bool = false

    public enum ConnectionFilter: String, CaseIterable, Identifiable {
        case all = "All Sockets"
        case established = "Established"
        case listening = "Listening"

        public var id: String { rawValue }
    }

    public enum RefreshInterval: Int, CaseIterable, Identifiable {
        case manual = 0
        case threeSeconds = 3
        case fiveSeconds = 5
        case tenSeconds = 10

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .manual: return "Manual"
            case .threeSeconds: return "Auto 3s"
            case .fiveSeconds: return "Auto 5s"
            case .tenSeconds: return "Auto 10s"
            }
        }
    }

    private var refreshTask: Task<Void, Never>?

    public init() {}

    public var filteredConnections: [NetworkConnection] {
        connections.filter { conn in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .established:
                matchesFilter = conn.isEstablished
            case .listening:
                matchesFilter = conn.state == "LISTEN"
            }

            if searchText.isEmpty {
                return matchesFilter
            }
            let query = searchText.lowercased()
            return matchesFilter && (
                conn.processName.lowercased().contains(query)
                || conn.localEndpoint.lowercased().contains(query)
                || conn.remoteEndpoint.lowercased().contains(query)
                || "\(conn.pid)".contains(query)
                || conn.proto.lowercased().contains(query)
            )
        }
    }

    private var lastRefreshTime: Date = .distantPast

    public func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        if !force && Date().timeIntervalSince(lastRefreshTime) < 1.0 {
            return
        }
        self.lastRefreshTime = Date()
        self.isLoading = true

        let results = await Task.detached(priority: .utility) { () -> [NetworkConnection] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-i", "-n", "-P", "-F", "pcnTP"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let output = String(data: data, encoding: .utf8) else { return [] }
                return Self.parseLsofOutput(output)
            } catch {
                return []
            }
        }.value

        self.connections = results
        self.isLoading = false
    }

    public func terminateProcess(pid: Int32) {
        kill(pid, SIGTERM)
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refresh(force: true)
        }
    }

    public func pauseAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isAutoRefreshing = false
    }

    public func resumeAutoRefresh() {
        guard refreshInterval != .manual else { return }
        restartTimer()
    }

    private func restartTimer() {
        refreshTask?.cancel()
        refreshTask = nil

        guard refreshInterval != .manual else {
            isAutoRefreshing = false
            return
        }

        isAutoRefreshing = true
        let intervalSeconds = refreshInterval.rawValue

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
                if Task.isCancelled { break }
                await self?.refresh(force: true)
            }
        }
    }

    nonisolated private static func parseLsofOutput(_ output: String) -> [NetworkConnection] {
        var results: [NetworkConnection] = []
        var currentPid: Int32 = 0
        var currentName: String = ""
        var currentProto: String = "TCP"
        var currentNameField: String = ""
        var currentState: String = ""

        let lines = output.components(separatedBy: "\n")

        for line in lines {
            guard !line.isEmpty else { continue }
            let prefix = line.prefix(1)
            let val = String(line.dropFirst())

            switch prefix {
            case "p":
                currentPid = Int32(val) ?? 0
            case "c":
                currentName = val
            case "P":
                currentProto = val.uppercased()
            case "n":
                currentNameField = val
            case "T":
                if val.hasPrefix("ST=") {
                    currentState = String(val.dropFirst(3))
                }
            case "f":
                // Finished a descriptor; record previous if valid
                if currentPid > 0 && !currentNameField.isEmpty && currentNameField != "*:*" {
                    let (local, remote) = parseEndpoints(currentNameField)
                    let st = currentState.isEmpty ? (currentProto == "UDP" ? "UDP" : "UNKNOWN") : currentState
                    let isEst = st == "ESTABLISHED"
                    let id = "\(currentPid)_\(currentNameField)_\(currentProto)_\(results.count)"

                    results.append(NetworkConnection(
                        id: id,
                        pid: currentPid,
                        processName: currentName,
                        proto: currentProto,
                        localEndpoint: local,
                        remoteEndpoint: remote,
                        state: st,
                        isEstablished: isEst
                    ))
                }
                currentNameField = ""
                currentState = ""
            default:
                break
            }
        }

        // Flush last item
        if currentPid > 0 && !currentNameField.isEmpty && currentNameField != "*:*" {
            let (local, remote) = parseEndpoints(currentNameField)
            let st = currentState.isEmpty ? (currentProto == "UDP" ? "UDP" : "UNKNOWN") : currentState
            let isEst = st == "ESTABLISHED"
            let id = "\(currentPid)_\(currentNameField)_\(currentProto)_\(results.count)"

            results.append(NetworkConnection(
                id: id,
                pid: currentPid,
                processName: currentName,
                proto: currentProto,
                localEndpoint: local,
                remoteEndpoint: remote,
                state: st,
                isEstablished: isEst
            ))
        }

        return results
    }

    nonisolated private static func parseEndpoints(_ field: String) -> (local: String, remote: String) {
        if field.contains("->") {
            let parts = field.components(separatedBy: "->")
            return (parts.first ?? field, parts.count > 1 ? parts[1] : "-")
        } else {
            return (field, "* (Listen)")
        }
    }
}
