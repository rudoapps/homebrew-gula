//
//  RegisterRepository.swift
//  Gula
//
//  Created by María Sogrob Garrido on 1/8/24.
//

import Foundation

class RegisterRepository: RegisterRepositoryProtocol {
    // MARK: - Properties
    private let registerRemoteDataSource: RegisterRemoteDataSource
    private let errorHandler: ErrorHandlerProtocol
    
    // MARK: - Init
    init(registerRemoteDataSource: RegisterRemoteDataSource, errorHandler: ErrorHandlerProtocol) {
        self.registerRemoteDataSource = registerRemoteDataSource
        self.errorHandler = errorHandler
    }
    
    // MARK: - Functions
    func createAccount() async throws {
        do {
            try await registerRemoteDataSource.createAccount()
        } catch {
            throw errorHandler.handle(error)
        }
    }
    
    func sendConfirmationEmail(with email: String) async throws {
        do {
            try await registerRemoteDataSource.sendConfirmationEmail(with: email)
        } catch {
            throw errorHandler.handle(error)
        }
    }
}
