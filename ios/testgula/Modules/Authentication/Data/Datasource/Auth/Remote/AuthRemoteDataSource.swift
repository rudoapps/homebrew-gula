//
//  AuthDataSource.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 10/7/24.
//

import Foundation
import TripleA

class AuthRemoteDataSource: AuthRemoteDataSourceProtocol {
    private let network: Network
    private let configuration: ConfigTripleA
    
    init(network: Network, configuration: ConfigTripleA = Config.shared) {
        self.network = network
        self.configuration = configuration
    }
    
    func login(with email: String, and password: String) async throws {
        let parameters = ["username": email,
                          "password": password]
        try await self.network.authenticator?.getNewToken(with: parameters, endpoint: nil)
    }
    
    func recoverPassword(with email: String) async throws {
        
    }
    
    func changePassword(password: String, id: String) async throws {
        
    }
    
    func logout() async throws {
        try await configuration.authenticator.logout()
        let endpoint = Endpoint(path: "api/users/logout", httpMethod: .post)
        _ = try await self.network.loadAuthorized(this: endpoint)
    }
}
