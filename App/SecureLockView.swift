import SwiftUI

struct SecureLockView: View {
    let onUnlock: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("보안 메모지").font(.headline).foregroundStyle(.black.opacity(0.75))
            Button("Touch ID로 열기", action: onUnlock)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
