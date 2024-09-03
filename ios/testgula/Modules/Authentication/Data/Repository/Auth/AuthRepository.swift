//
//  AuthRepository.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 10/7/24.
//

import Foundation

class AuthRepository: AuthRepositoryProtocol {
    // MARK: - Properties
    private let dataSource: AuthRemoteDataSourceProtocol
    private let errorHandler: ErrorHandlerProtocol
    
    // MARK: - Init
    init(dataSource: AuthRemoteDataSourceProtocol, errorHandler: ErrorHandlerProtocol) {
        self.dataSource = dataSource
        self.errorHandler = errorHandler
    }
    
    // MARK: - Functions
    func login(with email: String, and password: String) async throws {
        do {
            try await dataSource.login(with: email, and: password)
        } catch {
            throw errorHandler.handle(error)
        }
    }
    
    func recoverPassword(with email: String) async throws {
        do {
            try await dataSource.recoverPassword(with: email)
        } catch {
            throw errorHandler.handle(error)
        }
    }
    
    func changePassword(password: String, id: String) async throws {
        do {
            try await dataSource.changePassword(password: password, id: id)
        } catch {
            throw errorHandler.handle(error)
        }
    }
    
    func logout() async throws {
        do {
            try await dataSource.logout()
        } catch {
            throw errorHandler.handle(error)
        }
    }
}
