import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @EnvironmentObject var authService: GoogleAuthService
    @EnvironmentObject var photosService: GooglePhotosService
    @EnvironmentObject var wallpaperManager: WallpaperManager

    @State private var errorMessage: String? = nil

    var body: some View {
        Form {
            Section(header: Text("Google Photos Album")) {
                if let albumName = settings.appCreatedAlbumName {
                    if let albumUrl = settings.appCreatedAlbumProductUrl {
                        Link("Using album: \(albumName)", destination: albumUrl)
                    } else {
                        Text("Using album: \(albumName)")
                    }
                    if settings.showNoPicturesWarning {
                        if settings.albumPictureCount == 0 {
                            Text("Warning: No pictures found in this album.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            // This case should ideally not happen if showNoPicturesWarning is true
                            // but albumPictureCount is not 0. It implies album no longer exists.
                            Text("Warning: Selected album no longer exists or is inaccessible.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } else {
                        Text("Pictures in album: \(settings.albumPictureCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No app-managed album found.")
                    if settings.showNoPicturesWarning {
                        Text("Warning: The previously selected album no longer exists or is inaccessible. Please create a new one.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Button("Create New Album") {
                        Task {
                            await createAndSetAlbum()
                        }
                    }
                }
            }

            Section(header: Text("Wallpaper Change Settings")) {
                Picker("Change Frequency", selection: $settings.changeFrequency) {
                    ForEach(WallpaperChangeFrequency.allCases) { frequency in
                        Text(frequency.rawValue).tag(frequency)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Pick Randomly", isOn: $settings.pickRandomly)

                HStack {
                    Text("Minimum Picture Width:")
                    TextField("", value: $settings.minimumPictureWidth, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("px")
                }

                Toggle("Only Horizontal Photos", isOn: $settings.horizontalPhotosOnly)

                Picker("Fill Mode", selection: $settings.wallpaperFillMode) {
                    ForEach(WallpaperFillMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Button("Change Wallpaper Now") {
                    Task {
                        if let albumId = settings.appCreatedAlbumId {
                            do {
                                let mediaItems = try await photosService.searchPhotos(in: albumId)
                                settings.albumPictureCount = mediaItems.count
                                settings.showNoPicturesWarning = (mediaItems.count == 0)
                                print("SettingsView: Refreshed album picture count: \(settings.albumPictureCount). showNoPicturesWarning: \(settings.showNoPicturesWarning)")
                                if mediaItems.count == 0 {
                                    errorMessage = "No pictures found in the selected album. Please add photos to the album in Google Photos."
                                } else {
                                    await wallpaperManager.updateWallpaper()
                                }
                            } catch {
                                errorMessage = "Failed to refresh picture count or update wallpaper: \(error.localizedDescription)"
                                settings.showNoPicturesWarning = true
                            }
                        } else {
                            errorMessage = "No album selected. Please create or select an album first."
                            settings.showNoPicturesWarning = true
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func createAndSetAlbum() async {
        errorMessage = nil
        let defaultAlbumName = "GPhotoPaper"
        do {
            // First, check if an album with the default name already exists
            let existingAlbums = try await photosService.listAlbums(albumName: defaultAlbumName)
            if let existingAlbum = existingAlbums.first {
                settings.appCreatedAlbumId = existingAlbum.id
                settings.appCreatedAlbumName = existingAlbum.title
                UserDefaults.standard.set(existingAlbum.id, forKey: "appCreatedAlbumId")
                UserDefaults.standard.set(existingAlbum.title, forKey: "appCreatedAlbumName")
                return
            }

            // If no existing album, proceed to create a new one
            var album: GooglePhotosAlbum
            do {
                // Try creating with default name first
                album = try await photosService.createAppAlbum(albumName: defaultAlbumName)
            } catch let error as GooglePhotosServiceError {
                // If it's a conflict error (album already exists), try with UUID
                if case .networkError(let statusCode, _) = error, statusCode == 409 { // 409 Conflict
                    let uniqueAlbumName = "\(defaultAlbumName) - \(UUID().uuidString.prefix(8))"
                    album = try await photosService.createAppAlbum(albumName: uniqueAlbumName)
                } else {
                    throw error // Re-throw other errors
                }
            }

            settings.appCreatedAlbumId = album.id
            settings.appCreatedAlbumName = album.title
            UserDefaults.standard.set(album.id, forKey: "appCreatedAlbumId")
            UserDefaults.standard.set(album.title, forKey: "appCreatedAlbumName")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}