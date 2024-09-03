//
//  LoginView.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 4/7/24.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.presentationMode) var presentation
    @ObservedObject var viewModel: LoginViewModel
    @State private var errorTitle: LocalizedStringKey = ""
    @State private var errorMessage: LocalizedStringKey = ""
    @State private var showAlert = false
    
    var body: some View {
        ZStack {
            VStack {
                Text("LogIn")
                    .font(.system(size: 18))
                    .padding(.top, 18)
                Image(systemName: "photo.fill")
                    .resizable()
                    .frame(width: 83, height: 83)
                    .foregroundColor(Color.grayCustom4)
                    .clipShape(Circle())
                    .padding(.top, 24)
                VStack(spacing: 16) {
                    CustomTextField(text: $viewModel.email,
                                    isFieldValid: $viewModel.loginScreenUiState.isEmailValid,
                                    title: "email",
                                    placeholder: "writeEmail",
                                    errorMessage: "wrongEmailFormat",
                                    isFieldMandotory: true
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        CustomTextField(text: $viewModel.password,
                                        isFieldValid: $viewModel.loginScreenUiState.isPasswordValid,
                                        title: "password",
                                        placeholder: "password",
                                        errorMessage: "",
                                        type: .password,
                                        isFieldMandotory: true)
                        NavigationLink(destination: RecoverPasswordBuilder().build()) {
                            Text("forgotPassword")
                                .font(.system(size: 12))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding(.top, 24)
                CustomButton(buttonState: $viewModel.loginScreenUiState.loginButtonState,
                           type: .secondary,
                           buttonText: "LogIn") {
                    viewModel.login()
                }
                           .padding(.top, 20)
                Spacer()
                HStack(alignment: .center) {
                    Text("noAccountYet")
                        .font(.system(size: 14))
                    NavigationLink(destination: RegisterBuilder().build()) {
                        Text("register")
                            .font(.system(size: 14))
                            .bold()
                            .foregroundStyle(.black)
                            .underline()
                    }
                }
                .padding(.bottom, 20)
            }
            .onChange(of: viewModel.loginScreenUiState.authError) { _, error in
                guard let error else { return }
                set(this: error)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(errorTitle), message: Text(errorMessage), dismissButton: .default(Text("Accept"), action: {
                    viewModel.closeAlert()
                }))
            }
            .padding(.horizontal,16)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    presentation.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .resizable()
                        .frame(maxWidth: 16, maxHeight: 16)
                        .foregroundColor(.black)
                }
            }
        }
    }
        
    func set(this error: AuthError) {
        switch error {
        case .badCredentials(let message):
            errorTitle = "wrongCredentials"
            errorMessage = LocalizedStringKey(message)
        case .customError(let message):
            errorTitle = "tryAgain"
            errorMessage = LocalizedStringKey(message)
        case .generalError:
            errorTitle = "tryAgain"
            errorMessage = "generalError"
        }
        showAlert = true
    }
}
