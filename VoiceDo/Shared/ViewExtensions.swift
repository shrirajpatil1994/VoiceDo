import SwiftUI
import UserNotifications

// MARK: - Alert from VoiceDoError

extension View {
    /// Presents an alert when `error` is non-nil.
    func alert(error: Binding<VoiceDoError?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: { err in
            Text(err.localizedDescription)
        }
    }
}
