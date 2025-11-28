import SwiftUI

struct TUNSettingsView: View {
    @Binding var config: SeekerConfiguration

    var body: some View {
        Form {
            Section("TUN Device") {
                TextField("Device Name", text: $config.tunName)
                    .textFieldStyle(.roundedBorder)
                    .help("Virtual network interface name (e.g., utun4 on macOS)")

                TextField("IP Address", text: $config.tunIp)
                    .textFieldStyle(.roundedBorder)
                    .help("IP address of the TUN device")

                TextField("CIDR", text: $config.tunCidr)
                    .textFieldStyle(.roundedBorder)
                    .help("Network range routed to TUN device")
            }

            Section("Options") {
                Toggle("Bypass Direct Traffic", isOn: $config.tunBypassDirect)
                    .help("Bypass TUN for DIRECT action (better performance)")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}

#Preview {
    @Previewable @State var config = SeekerConfiguration.defaultConfiguration()
    TUNSettingsView(config: $config)
        .frame(width: 500, height: 400)
}
