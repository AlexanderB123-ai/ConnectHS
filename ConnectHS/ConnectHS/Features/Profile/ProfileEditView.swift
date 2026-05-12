import SwiftUI

/// Edit the existing profile fields from inside MainTabView. Mirrors
/// ProfileSetupView's collapsed-extras layout so the user sees a familiar
/// shape but understands they're editing rather than creating.
struct ProfileEditView: View {

    let user: AppUser
    @Bindable var authViewModel: AuthViewModel

    @State private var displayName: String
    @State private var highSchool: String
    @State private var gradYear: Int?
    @State private var showOptional: Bool
    @State private var saving = false
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    init(user: AppUser, authViewModel: AuthViewModel) {
        self.user = user
        self.authViewModel = authViewModel
        _displayName = State(initialValue: user.displayName)
        _highSchool = State(initialValue: user.highSchool ?? "")
        _gradYear = State(initialValue: user.gradYear)
        _showOptional = State(initialValue: user.highSchool?.isEmpty == false || user.gradYear != nil)
    }

    var body: some View {
        ZStack {
            Color.chCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Spacer()
                        .frame(height: Spacing.md)

                    Text("profile.edit.title")
                        .font(.chHeadline)
                        .foregroundStyle(.chInk)

                    VStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("profile.setup.name.placeholder")
                                .font(.chCaption)
                                .foregroundStyle(.chInkSoft)
                            TextField(String(localized: "profile.setup.name.placeholder"), text: $displayName)
                                .font(.chBody)
                                .textContentType(.givenName)
                                .padding(Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md).fill(.white)
                                )
                        }

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

                    if let saveError {
                        Text(saveError)
                            .font(.chCaption)
                            .foregroundStyle(.chError)
                    }

                    Spacer()
                }
            }
        }
        .navigationTitle(Text("profile.edit.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Text("profile.edit.save")
                            .foregroundStyle(isValid ? .chTether : .chInkSoft)
                    }
                }
                .disabled(!isValid || saving)
            }
        }
    }

    @ViewBuilder
    private var optionalFields: some View {
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("profile.setup.optional.school")
                    .font(.chCaption)
                    .foregroundStyle(.chInkSoft)
                TextField(String(localized: "profile.setup.optional.school.placeholder"), text: $highSchool)
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

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var gradYearBinding: Binding<Int> {
        Binding(
            get: { gradYear ?? 0 },
            set: { gradYear = $0 == 0 ? nil : $0 }
        )
    }

    private func save() async {
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            try await authViewModel.updateProfile(
                for: user,
                displayName: displayName,
                highSchool: highSchool,
                gradYear: gradYear
            )
            dismiss()
        } catch {
            saveError = String(localized: "auth.error.profile")
        }
    }
}
