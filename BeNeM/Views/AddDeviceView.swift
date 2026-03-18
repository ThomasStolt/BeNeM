import SwiftUI

struct AddDeviceView: View {
    @ObservedObject var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var ipAddress = ""
    @State private var deviceName = ""
    @State private var snmpCommunity = "public"
    @State private var isAdding = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Information")) {
                    TextField("IP Address", text: $ipAddress)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none)
                    
                    TextField("Device Name (Optional)", text: $deviceName)
                        .autocapitalization(.none)
                    
                    TextField("SNMP Community", text: $snmpCommunity)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addDevice()
                    }
                    .disabled(ipAddress.isEmpty || isAdding)
                }
            }
            .overlay {
                if isAdding {
                    ProgressView("Adding device...")
                }
            }
        }
    }
    
    private func addDevice() {
        isAdding = true
        Task {
            let name = deviceName.isEmpty ? nil : deviceName
            await viewModel.addDevice(ip: ipAddress, snmpPublic: snmpCommunity, name: name)
            isAdding = false
            dismiss()
        }
    }
}