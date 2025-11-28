import SwiftUI

struct GeneralSettingsView: View {
    @Binding var config: SeekerConfiguration

    var body: some View {
        Form {
            Section("Logging") {
                Toggle("Verbose Logging", isOn: $config.verbose)
            }

            Section("Mode") {
                Toggle("Gateway Mode", isOn: $config.gatewayMode)
                    .help("Allow LAN devices to use this proxy")

                Toggle("Redir Mode", isOn: $config.redirMode)
                    .help("Use iptables redirect instead of TUN (Linux only, TCP only)")
            }

            Section("Paths") {
                TextField("Database Path", text: $config.dbPath)
                    .textFieldStyle(.roundedBorder)
                    .help("Path to the database file, default is seeker.sqlite")

                TextField("GeoIP Database", text: $config.geoIp)
                    .textFieldStyle(.roundedBorder)
                    .help("Path to the GeoIP database file, or download url to the GeoIP database file, default is empty")
            }

            Section("Remote Clash Config URLs") {
                StringListEditor(
                    items: $config.remoteConfigUrls,
                    addButtonLabel: "Add URL"
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
    }
}

#Preview {
    @Previewable @State var config = SeekerConfiguration.defaultConfiguration()
    GeneralSettingsView(config: $config)
        .frame(width: 500, height: 400)
}
