//
//  ContentView.swift
//  seeker
//
//  Created by feichao on 2025/1/7.
//

import SwiftUI

struct ContentView: View {
    @Environment(GlobalStateVm.self) var globalState

    var body: some View {
        VStack(spacing: 20) {
            Text("Launch Daemon Management")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Daemon Status: \(globalState.daemonStatus.description)")
                Text("Seeker Status: \(globalState.seekerStatus)")
                    .foregroundColor(globalState.isStarted ? .green : .secondary)

                if let error = globalState.lastError {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Divider()

            VStack(spacing: 12) {
                Button(globalState.isStarted ? "Stop Seeker" : "Start Seeker") {
                    globalState.toggle()
                }
                .buttonStyle(.borderedProminent)
                .disabled(globalState.daemonStatus != .enabled)

                Button("Refresh Status") {
                    Task {
                        await globalState.updateSeekerStatus()
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            VStack(spacing: 12) {
                Text("Daemon Management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Register Daemon") {
                    do {
                        try globalState.registerDaemon()
                    } catch {
                        print(error)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(globalState.daemonStatus == .enabled)

                Button("Unregister Daemon") {
                    Task {
                        do {
                            try await globalState.unregisterDaemon()
                        } catch {
                            print(error)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(globalState.daemonStatus == .notRegistered)
            }

            if globalState.daemonStatus == .requiresApproval {
                Text("⚠️ Daemon requires approval in System Settings")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
    }
}

// #Preview {
//     ContentView()
// }
