//
//  RegisterUseCase.swift
//  Gula
//
//  Created by María Sogrob Garrido on 1/8/24.
//

import Foundation

enum RegisterError: Error, Equatable {
    case generalError
    case noInternet
}

class RegisterUseCase: RegisterUseCaseProtocol {
    // MARK: - Properties
    var registerRepository: RegisterRepositoryProtocol
    
    // MARK: - Init
    init(registerRepository: RegisterRepositoryProtocol) {
        self.registerRepository = registerRepository
    }
    
    // MARK: - Functions
    func createAccount() async throws {
        do {
            try await registerRepository.createAccount()
        } catch {
            throw handle(error)
        }
    }
    
    func sendConfirmationEmail(with email: String) async throws {
        do {
            try await registerRepository.sendConfirmationEmail(with: email)
        } catch {
            throw handle(error)
        }
    }
}

// MARK: - Extension
extension RegisterUseCase: ErrorHandlerProtocol {
    func handle(_ error: Error) -> Error {
        if let appError = error as? AppError {
            switch appError {
            case .noInternet:
                return RegisterError.noInternet
            default:
                return RegisterError.generalError
            }
        }
        return RegisterError.generalError
    }
}
