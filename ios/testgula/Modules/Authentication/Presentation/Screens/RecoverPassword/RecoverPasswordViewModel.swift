//
//  RecoverPasswordViewModel.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 17/7/24.
//

import Foundation

struct RecoverPasswordScreenUiState {
    var isEmailValid: Bool = false
    var sendButtonState: ButtonState = .disabled
    var authError: AuthError? = nil
    var hasEmailBeenSent: Bool = false
}

class RecoverPasswordViewModel: ObservableObject {
    @Published var email: String = "" {
        didSet {
            check(this: email)
        }
    }
    private let validationUseCase: ValidationUseCaseProtocol
    private let authUseCase: AuthUseCaseProtocol
    @Published var uiState = RecoverPasswordScreenUiState()
    
    init(validationUseCase: ValidationUseCaseProtocol, authUseCase: AuthUseCaseProtocol) {
        self.validationUseCase = validationUseCase
        self.authUseCase = authUseCase
    }
    
    @MainActor
    func recoverPassword() {
        Task {
            do {
                try await authUseCase.recoverPassword(with: email)
                uiState.hasEmailBeenSent = true
            } catch let error as AuthError {
                uiState.authError = error
            }
        }
    }
    
    func closeAlert() {
        uiState.authError = nil
    }
    
    private func checkIfReadyToSend()  {
        let isButtonDisabled = !uiState.isEmailValid || email.isEmpty
        uiState.sendButtonState = isButtonDisabled ? .disabled : .normal
    }
    
    private func check(this email: String?) {
        guard let email, !email.isEmpty else { return }
        uiState.isEmailValid = validationUseCase.validate(email: email)
        
        checkIfReadyToSend()
    }
}
