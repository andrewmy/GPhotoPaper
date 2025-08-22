import SwiftUI
import GoogleSignIn

@main
struct GPhotoPaperApp: App {
    @StateObject private var authService = GoogleAuthService()
    @State private var settings = SettingsModel()
    @State private var photosService: GooglePhotosService
    @State private var wallpaperManager: WallpaperManager

    init() {
        let authService = GoogleAuthService()
        _authService = StateObject(wrappedValue: authService)

        let settings = SettingsModel()
        _settings = State(wrappedValue: settings)

        let photosService = GooglePhotosService(authService: authService, settings: settings)
        _photosService = State(wrappedValue: photosService)

        _wallpaperManager = State(wrappedValue: WallpaperManager(photosService: photosService, settings: settings))

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
                .environmentObject(photosService)
                .environmentObject(wallpaperManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    Task {
                        if let albumId = settings.appCreatedAlbumId {
                            do {
                                let album = try await photosService.verifyAlbumExists(albumId: albumId)
                                if album == nil {
                                    settings.appCreatedAlbumId = nil
                                    settings.appCreatedAlbumName = nil
                                    settings.appCreatedAlbumProductUrl = nil
                                    settings.showNoPicturesWarning = true
                                    print("Album with ID \(albumId) no longer exists. Clearing stored album.")
                                } else {
                                    settings.appCreatedAlbumProductUrl = album?.productUrl
                                    let mediaItems = try await photosService.searchPhotos(in: albumId)
                                    settings.albumPictureCount = mediaItems.count
                                    settings.showNoPicturesWarning = (mediaItems.count == 0)
                                    print("GPhotoPaperApp: Album \(albumId) exists with \(mediaItems.count) pictures. showNoPicturesWarning: \(settings.showNoPicturesWarning)")
                                }
                            } catch {
                                print("Error during album verification or photo search on app start: \(error.localizedDescription)")
                                settings.showNoPicturesWarning = true // Show warning on error
                            }
                        }
                    }
                }
                .onChange(of: authService.user) { _ in
                    // When the user signs in or out, create a new SettingsModel
                    // to ensure we have a clean slate.
                    let newSettings = SettingsModel()
                    self.settings = newSettings
                    let newPhotosService = GooglePhotosService(authService: authService, settings: newSettings)
                    self.photosService = newPhotosService
                    self.wallpaperManager = WallpaperManager(photosService: newPhotosService, settings: newSettings)

                    // After new services are set up, re-check album if one was previously selected
                    if let albumId = newSettings.appCreatedAlbumId {
                        Task {
                            do {
                                if let album = try await newPhotosService.verifyAlbumExists(albumId: albumId) {
                                    newSettings.appCreatedAlbumProductUrl = album.productUrl
                                    let mediaItems = try await newPhotosService.searchPhotos(in: albumId)
                                    newSettings.albumPictureCount = mediaItems.count
                                    newSettings.showNoPicturesWarning = (mediaItems.count == 0)
                                } else {
                                    newSettings.appCreatedAlbumId = nil
                                    newSettings.appCreatedAlbumName = nil
                                    newSettings.appCreatedAlbumProductUrl = nil
                                    newSettings.showNoPicturesWarning = true
                                }
                            } catch {
                                print("Error re-verifying album on auth change: \(error.localizedDescription)")
                                newSettings.showNoPicturesWarning = true
                            }
                        }
                    }
                }
        }
    }
}

