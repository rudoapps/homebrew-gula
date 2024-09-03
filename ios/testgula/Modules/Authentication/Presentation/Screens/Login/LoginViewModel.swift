//
//  LoginViewModel.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 4/7/24.
//

import SwiftUI

struct LoginScreenUiState {
    var isEmailValid: Bool = false
    var isPasswordValid: Bool = true
    var loginButtonState: ButtonState = .disabled
    var authError: AuthError? = nil
}

class LoginViewModel: ObservableObject {
    @Published var email: String = "" {
        didSet {
            check(this: email)
        }
    }
    @Published var password: String = "" {
        didSet {
            checkIfReadyToLogin()
        }
    }
    @Published var loginScreenUiState = LoginScreenUiState()

    private let validationUseCase: ValidationUseCaseProtocol
    private let authUseCase: AuthUseCaseProtocol
    
    init(validationUseCase: ValidationUseCaseProtocol, authUseCase: AuthUseCaseProtocol) {
        self.validationUseCase = validationUseCase
        self.authUseCase = authUseCase
    }
    
    @MainActor
    func login() {
        Task {
            do {
                try await authUseCase.login(with: email, and: password)
            } catch let error as AuthError {
                loginScreenUiState.authError = error
            }
        }
    }
    
    private func checkIfReadyToLogin()  {
        let isLoginDisabled = !loginScreenUiState.isEmailValid || email.isEmpty || password.isEmpty
        loginScreenUiState.loginButtonState = isLoginDisabled ? .disabled : .normal
    }
    
    private func check(this email: String?) {
        guard let email, !email.isEmpty else { return }
        loginScreenUiState.isEmailValid = validationUseCase.validate(email: email)
        
        checkIfReadyToLogin()
    }
    
    func closeAlert() {
        loginScreenUiState.authError = nil
    }
}
