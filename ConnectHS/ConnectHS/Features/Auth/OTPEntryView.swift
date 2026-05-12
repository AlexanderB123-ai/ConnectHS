import SwiftUI

struct OTPEntryView: View {
    @Bindable var viewModel: AuthViewModel
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                Text("otp.title")
                    .font(.chDisplay)
                    .foregroundStyle(.chInk)
                    .accessibilityIdentifier("otp.title")

                Text("otp.subtitle \(viewModel.phoneNumber)")
                    .font(.chBody)
                    .foregroundStyle(.chInkSoft)

                TextField(String(localized: "otp.placeholder"), text: $viewModel.otpCode)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isCodeFocused)
                    .frame(height: 56)
                    .padding(.horizontal, Spacing.xxl)
                    .accessibilityIdentifier("otp.codeField")

                if let error = viewModel.otpError {
                    Text(error)
                        .font(.chCaption)
                        .foregroundStyle(.chError)
                }

                Button {
                    Task { await viewModel.verifyOTP() }
                } label: {
                    Text("otp.verify")
                        .font(.chHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(isCodeValid ? .chTether : .chInkSoft.opacity(0.3))
                        )
                }
                .disabled(!isCodeValid)
                .padding(.horizontal, Spacing.md)
                .accessibilityIdentifier("otp.verify")

                Button {
                    Task { await viewModel.sendOTP() }
                } label: {
                    Group {
                        if viewModel.isResendEnabled {
                            Text("otp.resend.now")
                        } else {
                            Text("otp.resend.countdown \(viewModel.resendCountdown)")
                        }
                    }
                    .font(.chCaption)
                    .foregroundStyle(viewModel.isResendEnabled ? .chTether : .chInkSoft)
                }
                .disabled(!viewModel.isResendEnabled)

                Spacer()
                Spacer()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isCodeFocused = true
            startResendTimer()
        }
    }

    private var isCodeValid: Bool {
        viewModel.otpCode.count == 6
    }

    private func startResendTimer() {
        viewModel.isResendEnabled = false
        viewModel.resendCountdown = 30
        // Drive the countdown from a Task instead of Timer.scheduledTimer.
        // Timer's closure is `@Sendable` and can't safely capture non-Sendable
        // `Timer` itself under Swift 6 strict concurrency.
        Task { @MainActor in
            while viewModel.resendCountdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                viewModel.resendCountdown -= 1
            }
            viewModel.isResendEnabled = true
        }
    }
}

#Preview {
    NavigationStack {
        OTPEntryView(viewModel: AuthViewModel())
    }
}
