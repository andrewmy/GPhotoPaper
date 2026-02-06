import AppKit // For NSWorkspace
import Foundation

@MainActor
final class WallpaperManager: ObservableObject {
    enum WallpaperUpdateTrigger {
        case timer
        case manual
    }

    @Published private(set) var lastSuccessfulUpdate: Date?
    @Published private(set) var nextScheduledUpdate: Date?
    @Published private(set) var lastUpdateError: String?

    private let photosService: any PhotosService
    private let settings: SettingsModel
    private var wallpaperTimer: Timer?

    private var inFlightUpdateTask: Task<Void, Never>?
    private var inFlightUpdateId: UUID?
    private var inFlightUpdateTrigger: WallpaperUpdateTrigger?
    private var lastAttemptDate: Date?

    init(photosService: any PhotosService, settings: SettingsModel) {
        self.photosService = photosService
        self.settings = settings
        self.lastSuccessfulUpdate = settings.lastSuccessfulWallpaperUpdate
    }

    func startWallpaperUpdates() {
        scheduleNextTimer()
    }

    func stopWallpaperUpdates() {
        wallpaperTimer?.invalidate()
        wallpaperTimer = nil
        nextScheduledUpdate = nil
    }

    func requestWallpaperUpdate(trigger: WallpaperUpdateTrigger) {
        if trigger == .manual {
            wallpaperTimer?.invalidate()
            wallpaperTimer = nil
            nextScheduledUpdate = nil
        }

        if let inFlightUpdateTask, let inFlightUpdateTrigger {
            switch (inFlightUpdateTrigger, trigger) {
            case (.timer, .manual):
                inFlightUpdateTask.cancel()
            case (.manual, .timer), (.timer, .timer):
                return
            case (.manual, .manual):
                inFlightUpdateTask.cancel()
            }
        }

        let updateId = UUID()
        inFlightUpdateId = updateId
        inFlightUpdateTrigger = trigger

        inFlightUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.inFlightUpdateId == updateId {
                    self.inFlightUpdateTask = nil
                    self.inFlightUpdateId = nil
                    self.inFlightUpdateTrigger = nil
                }
            }
            await self.updateWallpaper(trigger: trigger)
        }
    }

    private func intervalSeconds(for frequency: WallpaperChangeFrequency) -> TimeInterval? {
        switch frequency {
        case .never:
            return nil
        case .hourly:
            return 3600
        case .sixHours:
            return 21600
        case .daily:
            return 86400
        }
    }

    private func scheduleNextTimer() {
        wallpaperTimer?.invalidate()
        wallpaperTimer = nil

        guard let interval = intervalSeconds(for: settings.changeFrequency) else {
            nextScheduledUpdate = nil
            return
        }

        guard let selectedAlbumId = settings.selectedAlbumId, !selectedAlbumId.isEmpty else {
            nextScheduledUpdate = nil
            return
        }

        let now = Date()
        let lastSuccess = settings.lastSuccessfulWallpaperUpdate
        var due = (lastSuccess ?? now).addingTimeInterval(interval)

        // MVP: avoid changing wallpaper immediately on app launch.
        let minimumLeadTime: TimeInterval = 60
        let earliest = now.addingTimeInterval(minimumLeadTime)
        if due < earliest {
            due = earliest
        }

        // Avoid tight failure loops when due is already reached but updates keep failing.
        let minimumRetryDelay: TimeInterval = 300
        if let lastAttemptDate {
            let retryAfter = lastAttemptDate.addingTimeInterval(minimumRetryDelay)
            if due < retryAfter {
                due = retryAfter
            }
        }

        nextScheduledUpdate = due

        let timeInterval = max(1, due.timeIntervalSinceNow)
        wallpaperTimer = Timer(timeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wallpaperTimer?.invalidate()
                self.wallpaperTimer = nil
                self.requestWallpaperUpdate(trigger: .timer)
            }
        }

        if let wallpaperTimer {
            RunLoop.current.add(wallpaperTimer, forMode: .common)
        }
    }

    private func updateWallpaper(trigger: WallpaperUpdateTrigger) async {
        var shouldScheduleAfter = true
        defer {
            if shouldScheduleAfter {
                scheduleNextTimer()
            }
        }

        guard let albumId = settings.selectedAlbumId, !albumId.isEmpty else {
            print("Error: No OneDrive album selected.")
            return
        }

        do {
            lastAttemptDate = Date()

            let mediaItems = try await photosService.searchPhotos(inAlbumId: albumId)
            if Task.isCancelled { return }

            let filteredItems = filterMediaItems(mediaItems)
            if filteredItems.isEmpty {
                print("No photos found after applying filters.")
                return
            }

            let selectedPhoto: MediaItem
            if settings.pickRandomly {
                guard let randomItem = filteredItems.randomElement() else { return }
                selectedPhoto = randomItem
            } else {
                // Sequential picking
                let nextIndex = (settings.lastPickedIndex + 1) % filteredItems.count
                selectedPhoto = filteredItems[nextIndex]
                settings.lastPickedIndex = nextIndex
            }

            let wallpaperFileURL = try ensureWallpaperFileURL()

            let imageData = try await photosService.downloadImageData(for: selectedPhoto)
            if Task.isCancelled { return }
            try imageData.write(to: wallpaperFileURL, options: [.atomic])

            guard let screen = NSScreen.main else {
                print("Error: No main screen available.")
                return
            }
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]

            switch settings.wallpaperFillMode {
            case .fill:
                options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
                options[.allowClipping] = true
            case .fit:
                options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
                options[.allowClipping] = false
            case .stretch:
                options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
                options[.allowClipping] = false
            case .center:
                options[.imageScaling] = NSImageScaling.scaleNone.rawValue
                options[.allowClipping] = false
            }

            try NSWorkspace.shared.setDesktopImageURL(wallpaperFileURL, for: screen, options: options)
            print("Wallpaper updated successfully!")
            let now = Date()
            settings.lastSuccessfulWallpaperUpdate = now
            lastSuccessfulUpdate = now
            lastUpdateError = nil

        } catch is CancellationError {
            // Manual updates can cancel timer-driven updates; treat cancellation as expected.
            shouldScheduleAfter = false
        } catch {
            print("Error updating wallpaper: \(error.localizedDescription)")
            lastUpdateError = error.localizedDescription
        }
    }

    private func filterMediaItems(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            if settings.minimumPictureWidth > 0, let width = item.pixelWidth, Double(width) < settings.minimumPictureWidth {
                return false
            }

            if settings.horizontalPhotosOnly, let width = item.pixelWidth, let height = item.pixelHeight, width < height {
                return false
            }

            return true
        }
    }

    private func ensureWallpaperFileURL() throws -> URL {
        let baseDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDir = baseDir.appendingPathComponent("GPhotoPaper", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        return appDir.appendingPathComponent("wallpaper.jpg")
    }
}
