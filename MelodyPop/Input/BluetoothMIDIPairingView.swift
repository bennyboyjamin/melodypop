import CoreAudioKit
import SwiftUI

/// Apple's Bluetooth LE MIDI pairing screen. Once paired, the keyboard shows up as a normal
/// Core MIDI source and `MIDIPianoInput` connects to it automatically.
struct BluetoothMIDIPairingView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let central = CABTMIDICentralViewController()
        central.title = "Bluetooth Keyboards"
        return UINavigationController(rootViewController: central)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
