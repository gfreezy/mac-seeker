import SwiftUI

struct PerformanceSettingsView: View {
    @Binding var config: SeekerConfiguration

    var body: some View {
        Form {
            Section("Queue Settings (Linux)") {
                LabeledContent("Queue Number") {
                    Stepper(
                        value: $config.queueNumber,
                        in: 1...16
                    ) {
                        Text("\(config.queueNumber)")
                            .frame(width: 40)
                    }
                }
                .help("Number of queues (Linux only, more queues = better performance)")

                LabeledContent("Threads per Queue") {
                    Stepper(
                        value: $config.threadsPerQueue,
                        in: 1...16
                    ) {
                        Text("\(config.threadsPerQueue)")
                            .frame(width: 40)
                    }
                }
            }

            Section("Connection Timeouts") {
                TextField("Probe Timeout", text: $config.probeTimeout)
                    .textFieldStyle(.roundedBorder)
                    .help("Timeout for PROBE action to test direct connectivity")

                TextField("Ping Timeout", text: $config.pingTimeout)
                    .textFieldStyle(.roundedBorder)
                    .help("Timeout for pinging proxy servers")

                TextField("Connect Timeout", text: $config.connectTimeout)
                    .textFieldStyle(.roundedBorder)
                    .help("Timeout for connecting to proxy servers")
            }

            Section("I/O Timeouts") {
                TextField("Read Timeout", text: $config.readTimeout)
                    .textFieldStyle(.roundedBorder)
                    .help("Timeout for reading data from proxy servers")
                .help("Connection timeout when no data is read")

                TextField("Write Timeout", text: $config.writeTimeout)
                    .textFieldStyle(.roundedBorder)
                    .help("Timeout for writing data to proxy servers")
            }

            Section("Error Handling") {
                LabeledContent("Max Connect Errors") {
                    Stepper(
                        value: $config.maxConnectErrors,
                        in: 1...10
                    ) {
                        Text("\(config.maxConnectErrors)")
                            .frame(width: 40)
                    }
                }
                .help("Retries before switching to next proxy server")
            }

            Section("Ping URLs") {
                PingUrlListEditor(pingUrls: $config.pingUrls)
            }
            .help("URLs used to test proxy connectivity")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}

#Preview {
    @Previewable @State var config = SeekerConfiguration.defaultConfiguration()
    PerformanceSettingsView(config: $config)
        .frame(width: 500, height: 500)
}
