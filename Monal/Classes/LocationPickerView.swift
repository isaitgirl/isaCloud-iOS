//
//  LocationPickerView.swift
//  Monal
//
//  isaCloud: the map of the chat input to choose the place to send. The pin is in the middle of the map;
//  the place sent is the centre of the map when the user taps "Send this location".
//

import CoreLocation
import MapKit
import SwiftUI

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSend: (CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    /// kept so the location permission prompt is asked from this screen
    @State private var locationManager = CLLocationManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    center = context.region.center
                }

                // the pin stays in the middle of the map; its tip marks the place to send
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color("isaCloudPink"))
                    .offset(y: -18)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(Text("Location"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let center {
                        onSend(center)
                        dismiss()
                    }
                } label: {
                    Text("Send this location")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("isaCloudPink"))
                .disabled(center == nil)
                .padding()
                .background(.bar)
            }
            .onAppear {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }
}
