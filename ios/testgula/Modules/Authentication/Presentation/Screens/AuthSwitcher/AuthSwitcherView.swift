import SwiftUI
import TripleA

struct AuthSwitcherView: View {
    @EnvironmentObject var authenticator: AuthenticatorSUI
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    @StateObject var viewModel: AuthSwitcherViewModel
    
    var body: some View {
        switch authenticator.screen {
        case .login:
            switch deepLinkManager.screen {
            case .none:
                NavigationStack {
                    LoginViewBuilder().build()
                }
            case .newPassword:
                NavigationStack {
                    NewPasswordBuilder().build(with: deepLinkManager.id ?? "")
                }
            case .registerComplete:
                NavigationStack {
                    RegisterCompletedBuilder().build(with: deepLinkManager.id ?? "")
                }
            case .home:
                LogoutBuilder().build()
            }
        case .home:
            LogoutBuilder().build()
        }
    }
}
