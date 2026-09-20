import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct TestView: View {
    @State private var selectedFeature: MapFeature?
    
    var body: some View {
        Map(selection: $selectedFeature) {
            
        }
        .onChange(of: selectedFeature) { _, feature in
            if let feature = feature {
                Task {
                    let request = MKMapItemRequest(mapFeature: feature)
                    let item = try? await request.mapItem
                    print(item?.name ?? "")
                }
            }
        }
    }
}
