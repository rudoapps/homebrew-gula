//
//  RegisterViewModel.swift
//  Gula
//
//  Created by María Sogrob Garrido on 31/7/24.
//

import Foundation

struct RegisterScreenUIState {
    var isValidEmail: Bool = false
    var isValidPassword: Bool = false
    var isValidName: Bool = false
    var isValidRepeatPassword: Bool = false
    var registerError: RegisterError?
    var allFieldsOK: Bool = false
    var createAccountSucceeded: Bool = false
}

class RegisterViewModel: ObservableObject {
    // MARK: - Properties
    @Published var email: String = "" {
        didSet {
            checkEmail(email)
        }
    }
    @Published var password: String = "" {
        didSet {
            checkPassword(password)
        }
    }
    @Published var repeatPassword: String = "" {
        didSet {
            checkIfPasswordsMatch(this: repeatPassword)
        }
    }
    @Published var fullName: String = "" {
        didSet {
            checkName(this: fullName)
        }
    }
    @Published var isNavigationActive: Bool = false
    @Published var registerScreenUiState = RegisterScreenUIState()
    @Published var shouldNavigate: Bool = false
    @Published var showAlert: Bool = false
    
    private let validationUseCase: ValidationUseCaseProtocol
    private let registerUseCase: RegisterUseCaseProtocol
    
    // MARK: - Init
    init(validationUseCase: ValidationUseCaseProtocol, registerUseCase: RegisterUseCaseProtocol) {
        self.validationUseCase = validationUseCase
        self.registerUseCase = registerUseCase
    }
    
    // MARK: - Functions
    @MainActor
    func createAccount() {
          Task {
              do {
                  try await registerUseCase.createAccount()
                  registerScreenUiState.createAccountSucceeded = true
                  shouldNavigate = true
                  showAlert = false
              } catch let error as RegisterError {
                  registerScreenUiState.createAccountSucceeded = false
                  registerScreenUiState.registerError = error
                  shouldNavigate = false
                  showAlert = true
              }
          }
      }
    
    private func checkRegisterFields()  {
        let isLoginDisabled = !registerScreenUiState.isValidEmail || email.isEmpty || password.isEmpty || !registerScreenUiState.isValidName || repeatPassword.isEmpty || !registerScreenUiState.isValidPassword || !registerScreenUiState.isValidRepeatPassword
        registerScreenUiState.allFieldsOK = !isLoginDisabled
    }
    
    private func checkEmail(_ email: String?) {
        guard let email, !email.isEmpty else { return }
        registerScreenUiState.isValidEmail = validationUseCase.validate(email: email)
       
        checkRegisterFields()
    }
    
    private func checkPassword(_ password: String?) {
        guard let password, !password.isEmpty else { return }
        registerScreenUiState.isValidPassword = validationUseCase.validate(password: password)
       
        checkRegisterFields()
    }
    
    private func checkName(this name: String?) {
        guard let name else { return }
        registerScreenUiState.isValidName = !name.isEmpty
        
        checkRegisterFields()
    }
    
    private func checkIfPasswordsMatch(this repeatPassword: String?){
        guard let repeatPassword else { return }
        registerScreenUiState.isValidRepeatPassword = repeatPassword == password
        
        checkRegisterFields()
    }
    
    func closeAlert() {
        registerScreenUiState.registerError = nil
        showAlert = false
    }
}
