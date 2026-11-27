import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KaamosAuthSession") {
      AuthSessionPlugin.register(with: registrar)
    }
  }
}

/// OAuth2 sign-in sheet for Google and Microsoft.
///
/// `ASWebAuthenticationSession` shows the provider's page in a system sheet
/// (sharing Safari's cookies, not the app's memory) and closes it when the
/// page redirects to `callbackScheme`. The app gets only that final URL;
/// the Dart side checks `state` and exchanges the code with PKCE.
final class AuthSessionPlugin: NSObject, FlutterPlugin,
  ASWebAuthenticationPresentationContextProviding
{
  private var session: ASWebAuthenticationSession?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.kaamos.mail/oauth", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AuthSessionPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "authenticate",
      let args = call.arguments as? [String: Any],
      let urlString = args["url"] as? String,
      let url = URL(string: urlString),
      let scheme = args["callbackScheme"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    // One sheet at a time: a second tap would orphan the first result.
    if session != nil {
      result(FlutterError(code: "BUSY", message: "Accesso già in corso", details: nil))
      return
    }
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) {
      [weak self] callback, error in
      DispatchQueue.main.async {
        self?.session = nil
        if let callback {
          result(callback.absoluteString)
        } else if let error = error as? ASWebAuthenticationSessionError,
          error.code == .canceledLogin
        {
          result(FlutterError(code: "CANCELED", message: nil, details: nil))
        } else {
          result(
            FlutterError(code: "FAILED", message: error?.localizedDescription, details: nil))
        }
      }
    }
    session.presentationContextProvider = self
    self.session = session
    if !session.start() {
      self.session = nil
      result(FlutterError(code: "FAILED", message: "Impossibile aprire l'accesso", details: nil))
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
  }
}
