import SwiftUI

struct DNSSettingsView: View {
    @Binding var config: SeekerConfiguration

    var body: some View {
        Form {
            Section("DNS Settings") {
                    TextField("Start IP", text: $config.dnsStartIp)
                        .textFieldStyle(.roundedBorder)
                    .help("First IP in the fake IP range for DNS responses")

                TextField("Timeout", text: $config.dnsTimeout)
                    .textFieldStyle(.roundedBorder)
                    .help("Timeout for DNS queries")
            }

            Section("DNS Servers") {
                StringListEditor(
                    items: $config.dnsServers,
                    addButtonLabel: "Add DNS Server"
                )
            }
            .help("Upstream DNS servers. Supports tcp:// prefix for TCP DNS.")

            Section("DNS Listen Addresses") {
                StringListEditor(
                    items: $config.dnsListens,
                    addButtonLabel: "Add Listen Address"
                )
            }
            .help("Addresses to listen for DNS queries")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}

#Preview {
    @Previewable @State var config = SeekerConfiguration.defaultConfiguration()
    DNSSettingsView(config: $config)
        .frame(width: 500, height: 400)
}
