//
//  RegisterRemoteDataSourceProtocol.swift
//  Gula
//
//  Created by María Sogrob Garrido on 1/8/24.
//

import Foundation

protocol RegisterRemoteDataSourceProtocol {
    func createAccount() async throws
    func sendConfirmationEmail(with email: String) async throws
}
