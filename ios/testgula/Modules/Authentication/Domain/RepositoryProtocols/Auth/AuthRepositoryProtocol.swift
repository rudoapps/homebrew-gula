//
//  AuthRepositoryProtocol.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 10/7/24.
//

import Foundation

protocol AuthRepositoryProtocol {
    func login(with email: String, and password: String) async throws
    func recoverPassword(with email: String) async throws
    func changePassword(password: String, id: String) async throws
    func logout() async throws
}
