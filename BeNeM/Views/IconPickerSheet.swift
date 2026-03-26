// BeNeM/Views/IconPickerSheet.swift
import SwiftUI

struct IconPickerSheet: View {
    @Binding var symbol: String
    @Binding var accentColor: String
    @Environment(\.dismiss) private var dismiss

    private let symbols: [String] = [
        "server.rack", "network", "antenna.radiowaves.left.and.right",
        "wifi", "globe", "cloud.fill", "lock.shield.fill", "building.2.fill",
        "cpu", "externaldrive.connected.to.line.below.fill",
        "desktopcomputer", "laptopcomputer", "iphone",
        "shield.fill", "bolt.fill", "chart.bar.fill",
        "checkmark.seal.fill", "folder.fill", "gearshape.fill", "house.fill"
    ]

    private let palette: [Color] = [
        Color(hex: "#0A84FF"), Color(hex: "#30D158"), Color(hex: "#FF9F0A"),
        Color(hex: "#FF375F"), Color(hex: "#64D2FF"), Color(hex: "#BF5AF2"),
        Color(hex: "#FF6961"), Color(hex: "#5E5CE6"), Color(hex: "#32ADE6"),
        Color(hex: "#FFD60A")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Preview") {
                    HStack {
                        Spacer()
                        ServerIconView(symbol: symbol, accentColor: accentColor, size: 64)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(symbols, id: \.self) { sym in
                            Button {
                                symbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(symbol == sym ? Color(hex: accentColor) : .secondary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(symbol == sym ? Color(hex: accentColor).opacity(0.15) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(symbol == sym ? Color(hex: accentColor) : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(palette, id: \.self) { colour in
                            let hex = colour.toHex() ?? accentColor
                            Button {
                                accentColor = hex
                            } label: {
                                Circle()
                                    .fill(colour)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: accentColor.lowercased() == hex.lowercased() ? 3 : 0)
                                    )
                                    .shadow(color: colour.opacity(0.4), radius: 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Customise Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Reusable icon view — used in both the list rows and the picker preview.
struct ServerIconView: View {
    let symbol: String
    let accentColor: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(hex: accentColor))
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
