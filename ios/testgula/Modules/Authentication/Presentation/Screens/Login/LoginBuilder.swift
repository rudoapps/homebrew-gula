//
//  LoginBuilder.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 5/7/24.
//

import Foundation

class LoginViewBuilder {
    func build() -> LoginView {
        let network = Config.shared.network
        let errorHandler = ErrorHandlerManager()
        let dataSource = AuthRemoteDataSource(network: network)
        let repository = AuthRepository(dataSource: dataSource, errorHandler: errorHandler)
        let authUseCase = AuthUseCase(repository: repository)
        let validationUseCase = ValidationUseCase()
        let viewModel = LoginViewModel(validationUseCase: validationUseCase, authUseCase: authUseCase)
        let view = LoginView(viewModel: viewModel)
        return view
    }
}
