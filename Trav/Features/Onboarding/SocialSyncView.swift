import SwiftUI

struct SocialSyncView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var isGrantingAccess = false

    var body: some View {
        ZStack {
            OnboardingBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Unified Header
                OnboardingHeaderView(step: 3, onBack: onBack, onSkip: onSkip)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: TravSpacing.lg) {
                        // Title
                        VStack(alignment: .leading, spacing: TravSpacing.xs) {
                            Text("Find your friends")
                                .font(TravTypography.displayMedium())
                                .foregroundStyle(TravColors.primary)
                            Text("Connect your contacts to see where your crew is hanging out.")
                                .font(TravTypography.bodyMedium())
                                .foregroundStyle(TravColors.muted)
                        }
                        .padding(.top, TravSpacing.md)
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .travAppear()

                        // Animated Illustration
                        HStack {
                            Spacer()
                            AvatarCloudView()
                            Spacer()
                        }
                        .padding(.vertical, TravSpacing.md)
                        .travAppear(delay: 0.05)
                    }
                }
            }

            // Fixed bottom buttons
            VStack(spacing: TravSpacing.sm) {
                PrimaryButton(
                    title: isGrantingAccess ? "Enabling..." : "Allow Contacts",
                    isLoading: isGrantingAccess,
                    action: {
                        isGrantingAccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            isGrantingAccess = false
                            onContinue()
                        }
                    }
                )
                .travAppear(delay: 0.15)

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(TravColors.muted)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .travAppear(delay: 0.2)
            }
            .padding(TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden()
    }
}

// MARK: - Animated Avatar Cloud Illustration

struct AvatarCloudView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Central location marker
            ZStack {
                Circle()
                    .fill(TravColors.accentSoft)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(TravColors.accent)
            }
            .scaleEffect(animate ? 1.05 : 0.95)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animate)
            
            // Friend 1: Top Left
            FriendAvatar(initials: "JD", color: Color(red: 0.2, green: 0.6, blue: 0.9), size: 48)
                .offset(x: -75, y: -50)
                .offset(y: animate ? -5 : 5)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.2), value: animate)
            
            // Friend 2: Top Right
            FriendAvatar(initials: "SK", color: Color(red: 0.9, green: 0.3, blue: 0.6), size: 42)
                .offset(x: 75, y: -40)
                .offset(y: animate ? 4 : -4)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(0.4), value: animate)
            
            // Friend 3: Bottom Left
            FriendAvatar(initials: "ML", color: Color(red: 0.2, green: 0.8, blue: 0.5), size: 44)
                .offset(x: -85, y: 45)
                .offset(y: animate ? 3 : -3)
                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(0.1), value: animate)
            
            // Friend 4: Bottom Right
            FriendAvatar(initials: "RT", color: Color(red: 0.95, green: 0.7, blue: 0.2), size: 46)
                .offset(x: 80, y: 50)
                .offset(y: animate ? -4 : 4)
                .animation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true).delay(0.3), value: animate)
        }
        .frame(width: 250, height: 180)
        .onAppear { animate = true }
    }
}

struct FriendAvatar: View {
    let initials: String
    let color: Color
    let size: CGFloat
    
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                LinearGradient(
                    colors: [color, color.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color(red: 0.03, green: 0.03, blue: 0.04), lineWidth: 2)
            }
            .shadow(color: color.opacity(0.35), radius: 8, y: 4)
    }
}

#Preview {
    SocialSyncView(
        onContinue: {},
        onSkip: {},
        onBack: {}
    )
}

