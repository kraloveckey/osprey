import AppKit
import SwiftUI

public struct ProcessInspectorView: View {
    public enum SortField: String, CaseIterable {
        case cpu = "CPU %"
        case memory = "RAM"
        case name = "Name"
        case pid = "PID"
    }

    @Bindable var store: MetricsStore
    @State private var searchText: String = ""
    @State private var sortField: SortField = .cpu
    @State private var sortAscending: Bool = false
    @State private var feedbackMessage: String? = nil
    @State private var feedbackIsError: Bool = false
    @State private var selectedPid: Int32? = nil

    public init(store: MetricsStore) {
        self.store = store
    }

    private var processes: [ProcessUsage] {
        var list = store.topProcesses
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) || "\($0.pid)".contains(q)
            }
        }

        return list.sorted { a, b in
            switch sortField {
            case .cpu:
                return sortAscending ? a.cpuFraction < b.cpuFraction : a.cpuFraction > b.cpuFraction
            case .memory:
                return sortAscending ? a.memoryBytes < b.memoryBytes : a.memoryBytes > b.memoryBytes
            case .name:
                return sortAscending ? a.name.localizedCompare(b.name) == .orderedAscending : a.name.localizedCompare(b.name) == .orderedDescending
            case .pid:
                return sortAscending ? a.pid < b.pid : a.pid > b.pid
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Control & Search Bar
            searchAndFilterBar

            Divider()

            // Feedback Banner (if any process terminated)
            if let msg = feedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(msg)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button {
                        feedbackMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(feedbackIsError ? Theme.danger : Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background((feedbackIsError ? Theme.danger : Theme.accent).opacity(0.12))
            }

            // Table of processes
            tableHeader
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(processes, id: \.pid) { proc in
                        processRow(proc: proc)
                        Divider()
                    }
                }
            }

            Divider()

            // Footer
            footerBar
        }
        .frame(minWidth: 700, minHeight: 520)
        .background(Theme.background)
        .onAppear {
            store.refreshProcesses()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "cpu")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Process Activity & Task Manager")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.header)
                Text("Live per-process CPU time, memory footprint & instant termination controls")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            Button {
                store.refreshProcesses()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Search & Filter Bar

    private var searchAndFilterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                TextField("Search by name or PID…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            .frame(maxWidth: 280)

            Spacer()

            HStack(spacing: 8) {
                Text("Sort by:")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)

                Picker("", selection: $sortField) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 90)

                Button {
                    sortAscending.toggle()
                } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 11))
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(sortAscending ? "Ascending order" : "Descending order")
            }

            Text("\(processes.count) processes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.12))
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("PID")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 60, alignment: .leading)

            Text("PROCESS NAME")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            Text("CPU %")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 90, alignment: .trailing)

            Text("MEMORY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 90, alignment: .trailing)

            Text("ACTIONS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 140, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Process Row

    private func processRow(proc: ProcessUsage) -> some View {
        let isSelected = selectedPid == proc.pid

        return HStack(spacing: 8) {
            Text("\(proc.pid)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .frame(width: 60, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: "app.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                Text(displayProcessName(proc.name))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            // CPU with visual indicator
            HStack(spacing: 6) {
                Spacer()
                Text(String(format: "%.1f%%", proc.cpuFraction * 100))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(proc.cpuFraction > 0.5 ? Theme.danger : (proc.cpuFraction > 0.15 ? Theme.warning : Theme.text))
            }
            .frame(width: 90)

            // Memory
            Text(Fmt.memoryCompact(proc.memoryBytes))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(width: 90, alignment: .trailing)

            // Actions
            HStack(spacing: 6) {
                Button {
                    terminateProcess(pid: proc.pid, name: proc.name, force: false)
                } label: {
                    Text("Quit")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Gracefully terminate process (SIGTERM)")

                Button {
                    terminateProcess(pid: proc.pid, name: proc.name, force: true)
                } label: {
                    Text("Force Quit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.danger.opacity(0.15))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Immediately force kill process (SIGKILL)")
            }
            .frame(width: 140, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Theme.accent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPid = proc.pid
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Text("Tip: Click 'Force Quit' if an unresponsive process fails to close gracefully.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)

            Spacer()

            Button("Open Activity Monitor") {
                AppLauncher.openActivityMonitor()
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Process Termination Helper

    private func terminateProcess(pid: Int32, name: String, force: Bool) {
        let signal = force ? SIGKILL : SIGTERM
        let res = kill(pid, signal)
        if res == 0 {
            feedbackIsError = false
            feedbackMessage = "\(force ? "Force killed" : "Terminated") '\(name)' (PID: \(pid))."
            store.refreshProcesses()
        } else {
            feedbackIsError = true
            let err = String(cString: strerror(errno))
            feedbackMessage = "Failed to terminate '\(name)' (PID: \(pid)): \(err)"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if feedbackMessage?.contains("\(pid)") == true {
                feedbackMessage = nil
            }
        }
    }

    private func displayProcessName(_ name: String) -> String {
        guard ProcessInfo.processInfo.environment["OSPREY_SCREENSHOT_DEMO"] == "1" || UserDefaults.standard.bool(forKey: "privacyMaskEnabled") else { return name }
        let lower = name.lowercased()
        if lower.contains("ablation") {
            return "Xcode Build Service"
        }
        let userName = NSUserName().lowercased()
        if !userName.isEmpty && lower.contains(userName) {
            return "Developer Task"
        }
        return name
    }
}
