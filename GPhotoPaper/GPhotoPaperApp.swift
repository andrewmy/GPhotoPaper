import SwiftUI
import GoogleSignIn

@main
struct GPhotoPaperApp: App {
    @StateObject private var authService = GoogleAuthService()
    @StateObject private var settings = SettingsModel()

    init() {
        // Configure Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "551418211174-tp2fuecl5kqf70p4nj8rg1ap2e7uok3b.apps.googleusercontent.com"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(settings)
                // Initialize and provide photosService here, after authService is available
                .environmentObject(GooglePhotosService(authService: authService, settings: settings))
                .environmentObject(WallpaperManager(photosService: GooglePhotosService(authService: authService, settings: settings), settings: settings))
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

