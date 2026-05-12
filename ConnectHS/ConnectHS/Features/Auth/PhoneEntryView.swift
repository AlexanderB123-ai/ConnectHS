import SwiftUI

struct PhoneEntryView: View {
    @Bindable var viewModel: AuthViewModel
    @FocusState private var isPhoneFocused: Bool

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                Text("phone.title")
                    .font(.chDisplay)
                    .foregroundStyle(.chInk)
                    .accessibilityIdentifier("phone.title")

                Text("phone.subtitle")
                    .font(.chBody)
                    .foregroundStyle(.chInkSoft)
                    .accessibilityIdentifier("phone.subtitle")

                HStack(spacing: Spacing.sm) {
                    HStack(spacing: 2) {
                        Text("+")
                            .font(.chHeadline)
                            .foregroundStyle(.chInk)
                        TextField("1", text: $viewModel.countryCode)
                            .font(.chHeadline)
                            .foregroundStyle(.chInk)
                            .keyboardType(.numberPad)
                            .frame(width: 44)
                            .multilineTextAlignment(.leading)
                            .accessibilityLabel(Text("phone.countryCode.label"))
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(.white)
                    )

                    TextField("(555) 123-4567", text: $viewModel.phoneNumber)
                        .font(.chHeadline)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isPhoneFocused)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(.white)
                        )
                }
                .padding(.horizontal, Spacing.md)

                if let error = viewModel.otpError {
                    Text(error)
                        .font(.chCaption)
                        .foregroundStyle(.chError)
                }

                Button {
                    Task { await viewModel.sendOTP() }
                } label: {
                    Text("phone.send")
                        .font(.chHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(isPhoneValid ? .chTether : .chInkSoft.opacity(0.3))
                        )
                }
                .disabled(!isPhoneValid)
                .padding(.horizontal, Spacing.md)

                Spacer()
                Spacer()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: isAuthenticating) {
            OTPEntryView(viewModel: viewModel)
        }
        .onAppear { isPhoneFocused = true }
    }

    private var isPhoneValid: Bool {
        viewModel.phoneNumber.filter(\.isNumber).count >= 10
    }

    private var isAuthenticating: Binding<Bool> {
        Binding(
            get: {
                if case .authenticating = viewModel.state { return true }
                return false
            },
            set: { _ in }
        )
    }
}

#Preview {
    NavigationStack {
        PhoneEntryView(viewModel: AuthViewModel())
    }
}
