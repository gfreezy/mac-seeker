import SwiftUI

struct RulesListView: View {
    @Bindable var configService: ConfigurationService
    @State private var selectedRuleId: ParsedRule.ID?
    @State private var showingAddRule = false
    @State private var searchText = ""

    private var parsedRules: [ParsedRule] {
        configService.parsedRules
    }

    private var filteredRules: [ParsedRule] {
        if searchText.isEmpty {
            return parsedRules
        }
        return parsedRules.filter {
            $0.value.localizedCaseInsensitiveContains(searchText) ||
            $0.type.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.action.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            // Rules list
            List(selection: $selectedRuleId) {
                ForEach(filteredRules) { rule in
                    RuleRowView(rule: rule)
                        .tag(rule.id)
                }
                .onDelete(perform: deleteRules)
                .onMove(perform: moveRules)
            }
            .listStyle(.inset)
            .searchable(text: $searchText, prompt: "Search rules")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: { showingAddRule = true }) {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if selectedRuleId != nil {
                        Button(action: deleteSelectedRule) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
                .padding(8)
                .background(.bar)
            }
            .frame(idealWidth: 150)

            Group {
                // Rule editor
                if let selectedId = selectedRuleId,
                    let index = parsedRules.firstIndex(where: { $0.id == selectedId })
                {
                    RuleEditorView(
                        rule: Binding(
                            get: { parsedRules[index] },
                            set: { newRule in
                                // Only update if rule actually changed
                                guard parsedRules[index] != newRule else { return }
                                var rules = parsedRules
                                rules[index] = newRule
                                configService.parsedRules = rules
                                // Update selection to new ID since it's content-based
                                selectedRuleId = newRule.id
                            }
                        ),
                        availableGroups: configService.availableProxyGroupNames
                    )
                } else {
                    ContentUnavailableView(
                        "No Rule Selected",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Select a rule to edit or click + to add a new one")
                    )
                }
            }
            .frame(minWidth: 500, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(
                configService: configService,
                selectedRuleId: $selectedRuleId
            )
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        var rules = parsedRules
        rules.remove(atOffsets: offsets)
        configService.parsedRules = rules
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        var rules = parsedRules
        rules.move(fromOffsets: source, toOffset: destination)
        configService.parsedRules = rules
    }

    private func deleteSelectedRule() {
        guard let selectedId = selectedRuleId,
            let index = parsedRules.firstIndex(where: { $0.id == selectedId })
        else { return }
        var rules = parsedRules
        rules.remove(at: index)
        configService.parsedRules = rules
        selectedRuleId = nil
    }
}

struct RuleRowView: View {
    let rule: ParsedRule

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(rule.type.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ruleTypeColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)

                Spacer()

                Text(rule.action.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(actionColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }

            if !rule.value.isEmpty {
                Text(rule.value)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var ruleTypeColor: Color {
        switch rule.type {
        case .domain: return .blue
        case .domainSuffix: return .cyan
        case .domainKeyword: return .indigo
        case .ipCidr: return .purple
        case .geoip: return .orange
        case .match: return .gray
        }
    }

    private var actionColor: Color {
        switch rule.action {
        case .direct: return .green
        case .reject: return .red
        case .proxy: return .blue
        case .probe: return .orange
        }
    }
}

struct AddRuleSheet: View {
    @Bindable var configService: ConfigurationService
    @Binding var selectedRuleId: ParsedRule.ID?
    @Environment(\.dismiss) private var dismiss

    @State private var newRule = ParsedRule()

    var body: some View {
        VStack(spacing: 0) {
            Text("Add New Rule")
                .font(.headline)
                .padding()

            Divider()

            RuleEditorView(
                rule: $newRule,
                availableGroups: configService.availableProxyGroupNames
            )
            .padding()

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    configService.addRule(newRule, after: selectedRuleId)
                    selectedRuleId = newRule.id
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newRule.type.needsValue && newRule.value.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
}

struct RuleEditorView: View {
    @Binding var rule: ParsedRule
    let availableGroups: [String]

    @State private var actionType: ActionType = .direct
    @State private var selectedGroup: String = ""

    enum ActionType: String, CaseIterable {
        case direct = "Direct"
        case reject = "Reject"
        case proxy = "Proxy"
        case probe = "Probe"
    }

    // All available options including empty string (default)
    private var allGroupOptions: [String] {
        var options = [""]  // Empty string is valid (default proxy)
        options.append(contentsOf: availableGroups)
        return options
    }

    var body: some View {
        Form {
            Section("Rule Type") {
                Picker("Type", selection: $rule.type) {
                    ForEach(RuleType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            if rule.type.needsValue {
                Section("Match Value") {
                    TextField(rule.type.placeholder, text: $rule.value)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Action") {
                Picker("Action", selection: $actionType) {
                    ForEach(ActionType.allCases, id: \.self) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: actionType) { _, newValue in
                    updateRuleAction(newValue)
                }

                if actionType == .proxy || actionType == .probe {
                    Picker("Proxy Group", selection: $selectedGroup) {
                        ForEach(allGroupOptions, id: \.self) { group in
                            Text(group.isEmpty ? "(default)" : group).tag(group)
                        }
                    }
                    .onChange(of: selectedGroup) { _, newValue in
                        if actionType == .proxy {
                            rule.action = .proxy(groupName: newValue)
                        } else {
                            rule.action = .probe(groupName: newValue)
                        }
                    }
                }
            }

            Section("Preview") {
                Text(rule.toString())
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            syncActionType()
        }
        .onChange(of: rule.id) {
            syncActionType()
        }
    }

    private func syncActionType() {
        switch rule.action {
        case .direct:
            actionType = .direct
        case .reject:
            actionType = .reject
        case .proxy(let group):
            actionType = .proxy
            selectedGroup = group
        case .probe(let group):
            actionType = .probe
            selectedGroup = group
        }
    }

    private func updateRuleAction(_ newAction: ActionType) {
        switch newAction {
        case .direct:
            rule.action = .direct
        case .reject:
            rule.action = .reject
        case .proxy:
            rule.action = .proxy(groupName: selectedGroup)
        case .probe:
            rule.action = .probe(groupName: selectedGroup)
        }
    }
}

#Preview("Rules List") {
    let service = ConfigurationService(configPath: "/tmp/config.yml")
    RulesListView(configService: service)
        .frame(width: 650, height: 500)
        .onAppear {
            service.configuration = SeekerConfiguration.defaultConfiguration()
            service.isLoaded = true
        }
}

#Preview("Rule Editor") {
    @Previewable @State var rule = ParsedRule(
        type: .domainSuffix,
        value: "google.com",
        action: .proxy(groupName: "Proxy")
    )
    RuleEditorView(rule: $rule, availableGroups: ["Proxy", "Direct", "Auto"])
        .frame(width: 400, height: 400)
}

#Preview("Rule Row") {
    VStack(spacing: 10) {
        RuleRowView(rule: ParsedRule(type: .domain, value: "example.com", action: .direct))
        RuleRowView(
            rule: ParsedRule(
                type: .domainSuffix, value: "google.com", action: .proxy(groupName: "Proxy")))
        RuleRowView(rule: ParsedRule(type: .ipCidr, value: "192.168.0.0/16", action: .direct))
        RuleRowView(rule: ParsedRule(type: .match, value: "", action: .reject))
    }
    .padding()
    .frame(width: 300)
}
