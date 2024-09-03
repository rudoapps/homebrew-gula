//
//  NewPasswordViewModel.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 22/7/24.
//

import Foundation

struct NewPasswordScreenUiState {
    var hasChangePasswordSucceeded: Bool = false
    var arePasswordsEqual: Bool = false
    var isPasswordValid: Bool = true
    var allFieldsOk: Bool = false
    var authError: AuthError? = nil
}

class NewPasswordViewModel: ObservableObject {
    var userId: String
    @Published var uiState = NewPasswordScreenUiState()
    @Published var password: String = "" {
        didSet {
            check(this: password)
        }
    }
    @Published var repeatPassword: String = "" {
        didSet {
            checkIfReadyToChangePassword()
        }
    }
    private let validationUseCase: ValidationUseCaseProtocol
    private let authUseCase: AuthUseCaseProtocol
    
    init(userId: String, validationUseCase: ValidationUseCaseProtocol, authUseCase: AuthUseCaseProtocol) {
        self.userId = userId
        self.validationUseCase = validationUseCase
        self.authUseCase = authUseCase
    }
    
    @MainActor
    func changePassword() {
        Task {
            do {
                try await authUseCase.changePassword(password: password, id: userId)
                uiState.hasChangePasswordSucceeded = true
            } catch let error as AuthError {
                uiState.authError = error
            }
        }
    }
    
    func closeAlert() {
        uiState.authError = nil
    }
    
    private func checkIfReadyToChangePassword() {
        checkIfPasswordsMatch()
        self.uiState.allFieldsOk = uiState.isPasswordValid && !password.isEmpty && !repeatPassword.isEmpty && uiState.arePasswordsEqual
    }
    
    private func check(this password: String?) {
        guard let password else { return }
        uiState.isPasswordValid = false
        uiState.isPasswordValid = validationUseCase.validate(password: password)
        checkIfReadyToChangePassword()
    }
    
    private func checkIfPasswordsMatch() {
        uiState.arePasswordsEqual = password == repeatPassword
    }
}
