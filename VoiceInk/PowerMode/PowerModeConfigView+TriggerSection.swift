import SwiftUI
import AppKit

extension ConfigurationView {
    @ViewBuilder
    var triggerSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: Localization.PowerMode.whenToTriggerTitle)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Localization.PowerMode.applicationsTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        loadInstalledApps()
                        isShowingAppPicker = true
                    }) {
                        Label(Localization.PowerMode.addAppLabel, systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .help(Localization.PowerMode.addAppLabel)
                }

                if selectedAppConfigs.isEmpty {
                    HStack {
                        Spacer()
                        Text(Localization.PowerMode.noApplications)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding()
                    .background(CardBackground(isSelected: false))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50, maximum: 55), spacing: 10)], spacing: 10) {
                        ForEach(selectedAppConfigs) { appConfig in
                            appConfigItem(appConfig)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(Localization.PowerMode.websitesTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    TextField(Localization.PowerMode.websitePlaceholder, text: $newWebsiteURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Localization.PowerMode.websitePlaceholder)
                        .onSubmit {
                            addWebsite()
                        }

                    Button(action: addWebsite) {
                        Label(Localization.PowerMode.addButton, systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.accentColor)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .help(Localization.PowerMode.addButton)
                    .accessibilityLabel(Localization.PowerMode.addButton)
                    .disabled(newWebsiteURL.isEmpty)
                }

                if websiteConfigs.isEmpty {
                    HStack {
                        Spacer()
                        Text(Localization.PowerMode.noWebsites)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding()
                    .background(CardBackground(isSelected: false))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 10)], spacing: 10) {
                        ForEach(websiteConfigs) { urlConfig in
                            websiteConfigItem(urlConfig)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func appConfigItem(_ appConfig: AppConfig) -> some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appConfig.bundleIdentifier) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button(action: {
                    selectedAppConfigs.removeAll(where: { $0.id == appConfig.id })
                }) {
                    Label(Localization.PowerMode.deleteAction, systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .help(Localization.PowerMode.deleteAction)
                .accessibilityLabel(Localization.PowerMode.deleteAction)
                .offset(x: 6, y: -6)
            }
        }
        .frame(width: 50, height: 50)
        .background(CardBackground(isSelected: false, cornerRadius: 10))
    }

    @ViewBuilder
    private func websiteConfigItem(_ urlConfig: URLConfig) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)

            Text(urlConfig.url)
                .font(.system(size: 11))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: {
                websiteConfigs.removeAll(where: { $0.id == urlConfig.id })
            }) {
                Label(Localization.PowerMode.deleteAction, systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(Localization.PowerMode.deleteAction)
            .accessibilityLabel(Localization.PowerMode.deleteAction)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(CardBackground(isSelected: false, cornerRadius: 10))
    }
}
