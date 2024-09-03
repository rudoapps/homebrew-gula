//
//  RegisterRemoteDataSource.swift
//  Gula
//
//  Created by María Sogrob Garrido on 1/8/24.
//

import Foundation
import TripleA

class RegisterRemoteDataSource: RegisterRemoteDataSourceProtocol {
    private let network: Network
    
    init(network: Network) {
        self.network = network
    }
    
    func createAccount() async throws {}
    func sendConfirmationEmail(with email: String) async throws {}
}
