//
//  RegisterView.swift
//  Gula
//
//  Created by María Sogrob Garrido on 31/7/24.
//
import SwiftUI

struct RegisterView: View {
    @Environment(\.presentationMode) var presentation
    @ObservedObject var viewModel: RegisterViewModel
    @State private var errorTitle: LocalizedStringKey = ""
    @State private var errorMessage: LocalizedStringKey = ""
    @State private var sendButtonState: ButtonState = .disabled
    
    var body: some View {
        VStack {
            ScrollView {
                ZStack {
                    VStack {
                        Text("registerTitle")
                            .font(.system(size: 18))
                            .padding(.top, 18)
                        Image(systemName: "photo.fill")
                            .resizable()
                            .frame(width: 83, height: 83)
                            .foregroundColor(Color.grayCustom4)
                            .clipShape(Circle())
                            .padding(.top, 24)
                        VStack(spacing: 16) {
                            CustomTextField(
                                text: $viewModel.fullName,
                                isFieldValid: $viewModel.registerScreenUiState.isValidName,
                                title: "fullName",
                                placeholder: "fullName",
                                errorMessage: "",
                                isFieldMandotory: true
                            )
                            emailFieldView
                            passwordFieldsView
                        }
                        .padding(.top, 24)
                    }
                }
            }
            VStack(spacing: 8) {
                registerButtonView
                loginLinkView
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 16)
        .navigationBarBackButtonHidden()
        .onChange(of: viewModel.registerScreenUiState.allFieldsOK, { _, ok in
            sendButtonState = ok ? .normal : .disabled
        })
        .onChange(of: viewModel.registerScreenUiState.registerError, {_, error in
            guard let error = error else { return }
            set(this: error)
        })
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text(errorTitle),
                message: Text(errorMessage),
                dismissButton: .default(Text("Accept"), action: {
                    viewModel.closeAlert()
                })
            )
        }
    }
    
    private var emailFieldView: some View {
        VStack(alignment: .leading, spacing: 8) {
            CustomTextField(
                text: $viewModel.email,
                isFieldValid: $viewModel.registerScreenUiState.isValidEmail,
                title: "email",
                placeholder: "writeEmail",
                errorMessage: "wrongEmailFormat",
                isFieldMandotory: true
            )
        }
    }
    
    private var passwordFieldsView: some View {
        VStack(spacing: 16) {
            CustomTextField(
                text: $viewModel.password,
                isFieldValid: $viewModel.registerScreenUiState.isValidPassword,
                title: "password",
                subtitle: passwordSubtitle,
                placeholder: "password",
                errorMessage: "wrongPasswordFormat",
                type: .password,
                isFieldMandotory: true
            )
            
            VStack(alignment: .leading, spacing: 8) {
                CustomTextField(
                    text: $viewModel.repeatPassword,
                    isFieldValid: $viewModel.registerScreenUiState.isValidRepeatPassword,
                    title: "repeatPassword",
                    placeholder: "repeatPassword",
                    errorMessage: viewModel.password.isEmpty ? "" : "passwordsDoNotMatch",
                    type: .password,
                    isFieldMandotory: true
                )
            }
        }
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
    
    private var registerButtonView: some View {
        VStack {
            CustomButton(
                buttonState: $sendButtonState,
                type: .secondary,
                buttonText: "createAccount")
            {
                sendButtonState = .loading
                viewModel.createAccount()
                sendButtonState = .normal
            }
        }
    }
    
    private var loginLinkView: some View {
        HStack(alignment: .center) {
            Text("haveAccountText")
                .font(.system(size: 14))
                .foregroundColor(.black)
            Button(action: {
                presentation.wrappedValue.dismiss()
            }, label: {
                HStack(spacing: 0) {
                    Text("loginLowercased")
                        .underline()
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                }
            })
        }
    }
    
    private func set(this error: RegisterError) {
        switch error {
        case .generalError:
            errorTitle = "tryAgain"
            errorMessage = "generalError"
        case .noInternet:
            errorTitle = "tryAgain"
            errorMessage = "noInternet"
        }
    }
}
