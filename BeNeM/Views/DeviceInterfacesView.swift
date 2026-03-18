import SwiftUI

struct DeviceInterfacesView: View {
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "network")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                Text("Device Interfaces")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Interface details will be available here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("Interfaces")
        }
    }
}

#Preview {
    DeviceInterfacesView()
}