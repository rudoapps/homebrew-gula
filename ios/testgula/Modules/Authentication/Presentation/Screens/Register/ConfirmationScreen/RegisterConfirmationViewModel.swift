//
//  RegisterConfirmationVIewModel.swift
//  Gula
//
//  Created by María Sogrob Garrido on 1/8/24.
//

import Foundation

struct RegisterScreenConfirmationUIState {
    var sendEmailSucceeded: Bool = false
}

class RegisterConfirmationViewModel: ObservableObject {
    // MARK: - Properties
    var email: String
    private let registerUseCase: RegisterUseCaseProtocol
    @Published var uiState = RegisterScreenConfirmationUIState()
    
    
    // MARK: - Init
    init(email: String, registerUseCase: RegisterUseCaseProtocol) {
        self.email = email
        self.registerUseCase = registerUseCase
    }
    
    // MARK: - Functions
    @MainActor
    func checkConfirmationEmail() {
        Task {
            do {
                try await registerUseCase.sendConfirmationEmail(with: email)
                uiState.sendEmailSucceeded = true
            } catch  {
                uiState.sendEmailSucceeded = false
            }
        }
    }
    
    // TODO: GET DEEP LINK AND NAVIGATE TO REGISTER COMPLETED SCREEN
    func getRegisterDeepLink() {}
}
