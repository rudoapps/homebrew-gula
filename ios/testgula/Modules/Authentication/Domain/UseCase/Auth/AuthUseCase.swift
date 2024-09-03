//
//  AuthUseCase.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 5/7/24.
//

import Foundation

enum AuthError: Error, Equatable {
    case badCredentials(String)
    case customError(String)
    case generalError
}

class AuthUseCase: AuthUseCaseProtocol {
    // MARK: - Properties
    var repository: AuthRepositoryProtocol
    
    // MARK: - Init
    init(repository: AuthRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - Functions
    func login(with email: String, and password: String) async throws {
        do {
            try await repository.login(with: email, and: password)
        } catch {
            throw handle(error)
        }
    }
    
    func recoverPassword(with email: String) async throws {
        do {
            try await repository.recoverPassword(with: email)
        } catch {
            throw handle(error)
        }
    }
    
    func changePassword(password: String, id: String) async throws {
        do {
            try await repository.changePassword(password: password, id: id)
        } catch {
            throw handle(error)
        }
    }
    
    func logout() async throws {
        do {
            try await repository.logout()
        } catch {
            throw handle(error)
        }
    }
}

// MARK: - Extension
extension AuthUseCase: ErrorHandlerProtocol {
    func handle(_ error: Error) -> Error {
        if let appError = error as? AppError {
            switch appError {
            case .generalError, .noInternet:
                return AuthError.generalError
            case .badCredentials(let string):
                return AuthError.badCredentials(string)
            case .customError(let string):
                return AuthError.customError(string)
            }
        }
        return AuthError.generalError
    }
}
