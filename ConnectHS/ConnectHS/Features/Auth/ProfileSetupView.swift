import SwiftUI

struct ProfileSetupView: View {
    @Bindable var viewModel: AuthViewModel
    let user: AppUser

    @State private var showOptional = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Spacer()
                        .frame(height: Spacing.xl)

                    Text("profile.setup.title")
                        .font(.chDisplay)
                        .foregroundStyle(.chInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.md)

                    VStack(spacing: Spacing.md) {
                        TextField(String(localized: "profile.setup.name.placeholder"), text: $viewModel.displayName)
                            .font(.chBody)
                            .textContentType(.givenName)
                            .submitLabel(.go)
                            .focused($isNameFocused)
                            .onSubmit { Task { if isFormValid { await viewModel.completeProfile(for: user) } } }
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md).fill(.white)
                            )
                            .accessibilityIdentifier("profile.setup.name")

                        Button {
                            withAnimation { showOptional.toggle() }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: showOptional ? "chevron.down" : "chevron.right")
                                Text("profile.setup.more")
                            }
                            .font(.chCaption)
                            .foregroundStyle(.chInkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if showOptional {
                            optionalFields
                        }
                    }
                    .padding(.horizontal, Spacing.md)

                    if let error = viewModel.otpError {
                        Text(error)
                            .font(.chCaption)
                            .foregroundStyle(.chError)
                    }

                    Button {
                        Task { await viewModel.completeProfile(for: user) }
                    } label: {
                        Text("profile.setup.cta")
                            .font(.chHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(isFormValid ? .chTether : .chInkSoft.opacity(0.3))
                            )
                    }
                    .disabled(!isFormValid)
                    .padding(.horizontal, Spacing.md)
                    .accessibilityIdentifier("profile.setup.cta")

                    Spacer()
                        .frame(height: Spacing.xxl)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.displayName.isEmpty {
                viewModel.displayName = user.displayName
            }
            // Drop straight into the name field so the keyboard is up before
            // the user has time to read the placeholder. Shaves ~1s off the
            // sub-60s onboarding tempo target in spec/03.
            isNameFocused = true
        }
    }

    private var optionalFields: some View {
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("profile.setup.optional.school")
                    .font(.chCaption)
                    .foregroundStyle(.chInkSoft)
                TextField(String(localized: "profile.setup.optional.school.placeholder"), text: $viewModel.highSchool)
                    .font(.chBody)
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md).fill(.white)
                    )
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("profile.setup.optional.gradYear")
                    .font(.chCaption)
                    .foregroundStyle(.chInkSoft)
                Picker("profile.setup.optional.gradYear", selection: gradYearBinding) {
                    Text("profile.setup.optional.gradYear.select").tag(0)
                    ForEach(2020...2035, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
                .tint(.chInk)
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md).fill(.white)
                )
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var isFormValid: Bool {
        !viewModel.displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var gradYearBinding: Binding<Int> {
        Binding(
            get: { viewModel.gradYear ?? 0 },
            set: { viewModel.gradYear = $0 == 0 ? nil : $0 }
        )
    }
}

#Preview {
    NavigationStack {
        ProfileSetupView(
            viewModel: AuthViewModel(),
            user: AppUser(
                id: UUID(),
                displayName: "",
                authMethod: .phone,
                timezone: "America/New_York",
                isAgeVerified: true,
                isBlocked: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}
