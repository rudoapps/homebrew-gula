//
//  RegisterConfirmationBuilder.swift
//  Gula
//
//  Created by María Sogrob Garrido on 1/8/24.
//

import Foundation

class RegisterConfirmationBuilder {
    func build(with email: String) -> RegisterConfirmationView {
        let network = Config.shared.network
        let registerRemoteDataSource = RegisterRemoteDataSource(network: network)
        let errorHandler = ErrorHandlerManager()
        let registerRepository = RegisterRepository(registerRemoteDataSource: registerRemoteDataSource, errorHandler: errorHandler)
        let registerUseCase = RegisterUseCase(registerRepository: registerRepository)
        let viewModel = RegisterConfirmationViewModel(email: email, registerUseCase: registerUseCase)
        let view = RegisterConfirmationView(viewModel: viewModel)
        return view
    }
}
