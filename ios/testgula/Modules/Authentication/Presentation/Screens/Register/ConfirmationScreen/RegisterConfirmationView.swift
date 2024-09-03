//
//  RegisterConfirmationScreen.swift
//  Gula
//
//  Created by María Sogrob Garrido on 1/8/24.
//

import SwiftUI

struct RegisterConfirmationView: View {
    @ObservedObject var viewModel: RegisterConfirmationViewModel
    @Environment(\.presentationMode) var presentation
    
    var body: some View {
        ZStack {
            VStack(spacing: 50) {
                Text("Gula")
                    .font(.system(size: 20))
                    .padding(.top, 18)
                Image(systemName: "pencil")
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 50)
                            .stroke(.gray)
                    )
                
                VStack(spacing: 35) {
                    Text("confirmEmailTitle")
                        .font(.system(size: 20))
                    Text("emailSentInfoRegister, \(viewModel.email)")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .font(.system(size: 18))
                    VStack(spacing: 0) {
                        Text("emailNotReceived")
                            .font(.system(size: 14))
                        Button {
                            presentation.wrappedValue.dismiss()
                        } label: {
                            Text("sendAgain")
                                .font(.system(size: 14))
                                .foregroundStyle(.black)
                                .underline()
                        }
                    }
                }
                Spacer()
            }
            .toolbar(.hidden, for: .navigationBar)
            .padding(.horizontal, 16)
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            viewModel.checkConfirmationEmail()
        }
    }
}
