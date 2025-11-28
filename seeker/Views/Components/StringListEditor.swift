import SwiftUI

struct StringListEditor: View {
    @Binding var items: [String]
    var addButtonLabel: String = "Add Item"

    @State private var showingAddItem = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    Text(items[index])
                        .font(.system(.body, design: .monospaced))

                    Spacer()

                    Button(action: {
                        items.remove(at: index)
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }

            Button(action: { showingAddItem = true }) {
                Label(addButtonLabel, systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingAddItem) {
            AddStringItemSheet(items: $items)
        }
    }
}

struct AddStringItemSheet: View {
    @Binding var items: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var newValue: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Item")
                .font(.headline)

            TextField("Value", text: $newValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addAndDismiss()
                }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newValue.isEmpty)
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }

    private func addAndDismiss() {
        guard !newValue.isEmpty else { return }
        items.append(newValue)
        dismiss()
    }
}

struct PingUrlListEditor: View {
    @Binding var pingUrls: [PingUrl]

    @State private var showingAddPingUrl = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($pingUrls) { $pingUrl in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pingUrl.host):\(pingUrl.port)\(pingUrl.path)")
                            .font(.system(.body, design: .monospaced))
                    }

                    Spacer()

                    Button(action: {
                        if let index = pingUrls.firstIndex(where: { $0.id == pingUrl.id }) {
                            pingUrls.remove(at: index)
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }

            Button(action: { showingAddPingUrl = true }) {
                Label("Add Ping URL", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingAddPingUrl) {
            AddPingUrlSheet(pingUrls: $pingUrls)
        }
    }
}

struct AddPingUrlSheet: View {
    @Binding var pingUrls: [PingUrl]
    @Environment(\.dismiss) private var dismiss

    @State private var host: String = ""
    @State private var port: String = "80"
    @State private var path: String = "/"

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Ping URL")
                .font(.headline)

            Form {
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)

                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)

                TextField("Path", text: $path)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    if let portNum = Int(port) {
                        let newPingUrl = PingUrl(host: host, port: portNum, path: path)
                        pingUrls.append(newPingUrl)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.isEmpty || Int(port) == nil)
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}

#Preview("String List Editor") {
    @Previewable @State var items = ["223.5.5.5:53", "114.114.114.114:53"]
    StringListEditor(items: $items)
        .padding()
        .frame(width: 400)
}

#Preview("Ping URL List Editor") {
    @Previewable @State var pingUrls = [
        PingUrl(host: "www.google.com", port: 80, path: "/"),
        PingUrl(host: "www.baidu.com", port: 443, path: "/")
    ]
    PingUrlListEditor(pingUrls: $pingUrls)
        .padding()
        .frame(width: 400)
}
