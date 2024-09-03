//
//  RegisterBuilder.swift
//  Gula
//
//  Created by María Sogrob Garrido on 31/7/24.
//

import Foundation

class RegisterBuilder {
    func build() -> RegisterView {
        let network = Config.shared.network
        let errorHandler = ErrorHandlerManager()
        let registerRemoteDataSource = RegisterRemoteDataSource(network: network)
        let registerRemoteRepository = RegisterRepository(registerRemoteDataSource: registerRemoteDataSource, errorHandler: errorHandler)
        let authUseCase = RegisterUseCase(registerRepository: registerRemoteRepository)
        let validationUseCase = ValidationUseCase()
        let viewModel = RegisterViewModel(validationUseCase: validationUseCase, registerUseCase: authUseCase)
        let view = RegisterView(viewModel: viewModel)
        return view
    }
}
