//
//  NewPasswordView.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 22/7/24.
//

import SwiftUI

struct NewPasswordView: View {
    @EnvironmentObject var deeplinkManager: DeepLinkManager
    @ObservedObject var viewModel: NewPasswordViewModel
    @State private var alertTitle: LocalizedStringKey = ""
    @State private var alertMessage: LocalizedStringKey = ""
    @State private var showAlert = false
    @State private var sendButtonState: ButtonState = .disabled
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("writeNewPassword")
                .font(.system(size: 18))
                .padding(.top, 36)
            VStack(alignment: .leading, spacing: 0) {
                CustomTextField(text: $viewModel.password,
                                isFieldValid: $viewModel.uiState.isPasswordValid,
                                title: "password",
                                subtitle: passwordSubtitle,
                                placeholder: "newPassword",
                                errorMessage: "wrongPasswordFormat",
                                type: .password,
                                isFieldMandotory: true)
            }
            CustomTextField(text: $viewModel.repeatPassword,
                            isFieldValid: $viewModel.uiState.arePasswordsEqual,
                            title: "repeatPassword",
                            placeholder: "repeatNewPassword",
                            errorMessage: "passwordsDoNotMatch",
                            type: .password,
                            isFieldMandotory: true)
            CustomButton(buttonState: $sendButtonState,
                         type: .secondary,
                         buttonText: "changePassword") {
                sendButtonState = .loading
                viewModel.changePassword()
            }
            Spacer()
        }
        .onChange(of: viewModel.uiState.allFieldsOk, { _, ok in
            sendButtonState = ok ? .normal : .disabled
        })
        .onChange(of: viewModel.uiState.authError, { _, error in
            guard let error = error else { return }
            sendButtonState = .disabled
            set(this: error)
        })
        .onChange(of: viewModel.uiState.hasChangePasswordSucceeded, { _, show in
            sendButtonState = .normal
            if !show { return }
            alertTitle = "passwordUpdated"
            alertMessage = "passwordUpdatedInfo"
            showAlert = true
        })
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("Accept"), action: {
                if viewModel.uiState.hasChangePasswordSucceeded {
                    deeplinkManager.screen = .none
                }
                viewModel.closeAlert()
            }))
        }
        .padding(.horizontal, 16)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("newPassword")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarLeading) {
                HStack {
                    Button {
                        deeplinkManager.screen = .none
                    } label: {
                        Image(systemName: "xmark")
                            .resizable()
                            .frame(width: 16, height: 16)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .toolbarBackground(.grayCustom5, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
    
    private var passwordSubtitle: Text {
        Text("passwordFirstText")
        + Text(" ")
        + Text("passwordSecondTextBold").bold()
        + Text(" ")
        + Text("passwordThirdText")
        + Text(" ")
        + Text("passwordFourthTextBold").bold()
    }
    
    func set(this error: AuthError) {
        switch error {
        case .badCredentials(let message):
            alertTitle = "wrongCredentials"
            alertMessage = LocalizedStringKey(message)
        case .customError(let message):
            alertTitle = "tryAgain"
            alertMessage = LocalizedStringKey(message)
        case .generalError:
            alertTitle = "tryAgain"
            alertMessage = "generalError"
        }
        showAlert = true
    }
}
