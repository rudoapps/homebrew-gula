import Foundation

class AuthSwitcherViewBuilder {
    func build() -> AuthSwitcherView {
        let viewModel = AuthSwitcherViewModel()
        let view = AuthSwitcherView(viewModel: viewModel)
        return view
    }
}
