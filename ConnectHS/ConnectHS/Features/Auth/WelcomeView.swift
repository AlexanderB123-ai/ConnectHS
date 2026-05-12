import SwiftUI
import AuthenticationServices
import CryptoKit
import os

struct WelcomeView: View {
    @Bindable var viewModel: AuthViewModel

    @State private var siwaErrorMessage: String?
    private let logger = Logger(subsystem: "com.connecths.app", category: "SIWA")

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.chCream, .chPeach],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                Text("welcome.title")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.chInk)
                    .accessibilityIdentifier("welcome.title")

                Text("welcome.tagline")
                    .font(.chBody)
                    .foregroundStyle(.chInkSoft)
                    .multilineTextAlignment(.center)

                Spacer()

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                    let nonce = Self.randomNonceString()
                    request.nonce = Self.sha256(nonce)
                    viewModel.appleNonce = nonce
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))

                NavigationLink {
                    PhoneEntryView(viewModel: viewModel)
                } label: {
                    Text("welcome.continue.phone")
                        .font(.chHeadline)
                        .foregroundStyle(.chInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(.chInk, lineWidth: 1.5)
                        )
                }
                .accessibilityIdentifier("welcome.continue.phone")

                if let message = siwaErrorMessage {
                    Text(message)
                        .font(.chCaption)
                        .foregroundStyle(.chError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.md)
                }

                Text("welcome.terms")
                    .font(.chMicro)
                    .foregroundStyle(.chInkSoft)
                    .multilineTextAlignment(.center)
                    .tint(.chTether)

                Spacer()
                    .frame(height: Spacing.md)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            siwaErrorMessage = nil
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                logger.error("SIWA success but credential not ASAuthorizationAppleIDCredential")
                siwaErrorMessage = "unexpected credential type"
                return
            }
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                logger.error("SIWA success but identityToken missing")
                siwaErrorMessage = "apple didn't return an id token"
                return
            }
            guard let nonce = viewModel.appleNonce else {
                logger.error("SIWA success but local nonce missing")
                siwaErrorMessage = "missing nonce — try again"
                return
            }
            Task {
                await viewModel.signInWithApple(
                    idToken: idToken,
                    nonce: nonce,
                    fullName: credential.fullName
                )
            }
        case .failure(let error):
            let nsError = error as NSError
            logger.error("""
                SIWA failure: domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code, privacy: .public) \
                description=\(nsError.localizedDescription, privacy: .public) \
                userInfo=\(nsError.userInfo.description, privacy: .public)
                """)
            siwaErrorMessage = "apple sign in failed (\(nsError.code)): \(nsError.localizedDescription)"
        }
    }

    // MARK: - Apple Sign In helpers

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { return "" }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    NavigationStack {
        WelcomeView(viewModel: AuthViewModel())
    }
}
