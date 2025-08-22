# OneDrive Integration Battle Plan

This document outlines the detailed plan to integrate OneDrive for photo management, replacing the current Google Photos integration.

## Phase 1: OneDrive API Integration (Backend)

1.  **OneDrive Authentication Service (`OneDriveAuthService.swift`):**
    *   **Research:** Identify the correct OAuth 2.0 flow for macOS applications to authenticate with OneDrive (Microsoft Graph API). This will likely involve registering an application with Microsoft Azure AD.
    *   **Implementation:**
        *   Create a new `OneDriveAuthService` class (similar to `GoogleAuthService`).
        *   Implement methods for signing in, signing out, and refreshing access tokens.
        *   Handle URL callbacks for OAuth redirection.
        *   Store authentication tokens securely (e.g., Keychain).

2.  **OneDrive Photos Service (`OneDrivePhotosService.swift`):**
    *   **Research:** Understand Microsoft Graph API endpoints for listing albums/folders, creating albums/folders, and fetching photos within a specific album/folder.
    *   **Implementation:**
        *   Create a new `OneDrivePhotosService` class (similar to `GooglePhotosService`).
        *   Implement methods for:
            *   `listAlbums()`: To retrieve a list of photo albums/folders from OneDrive.
            *   `createAlbum(name: String)`: To create a new album/folder.
            *   `searchPhotos(in albumId: String)`: To fetch media items (photos) from a specified album/folder.
            *   `verifyAlbumExists(albumId: String)`: To check if a given album/folder still exists.
        *   Handle API errors and network issues gracefully.

## Phase 2: UI and App Logic Adaptation (Frontend)

1.  **Update `GPhotoPaperApp.swift`:**
    *   Replace `GoogleAuthService` and `GooglePhotosService` with `OneDriveAuthService` and `OneDrivePhotosService`.
    *   Adjust initialization and environment object passing to use the new OneDrive services.
    *   Modify the `onAppear` and `onChange(of: authService.user)` blocks to use the OneDrive album verification and photo counting logic.

2.  **Update `SettingsModel.swift`:**
    *   Remove Google Photos specific properties (e.g., `appCreatedAlbumId`, `appCreatedAlbumName`, `appCreatedAlbumProductUrl`) if they are tightly coupled to Google Photos.
    *   Add new properties for OneDrive album ID, name, and URL.

3.  **Update `SettingsView.swift`:**
    *   **Authentication UI:** Replace Google Sign-In button with OneDrive Sign-In.
    *   **Album Management UI:**
        *   Replace "Create New Album" with options to "Select Existing Album" or "Create New Album" for OneDrive.
        *   Implement UI to display a list of OneDrive albums/folders for user selection.
        *   Update the warning messages and album link display to reflect OneDrive album details.
    *   Ensure the "Change Wallpaper Now" button correctly triggers the OneDrive photo fetching and wallpaper update.

4.  **Update `WallpaperManager.swift`:**
    *   Ensure it uses the `OneDrivePhotosService` to fetch photos. The core logic for setting wallpaper and filtering should remain largely the same.

## Phase 3: Cleanup and Testing

1.  **Remove Google Photos related code:** Delete `GoogleAuthService.swift`, `GooglePhotosService.swift`, and any other Google Photos specific code.
2.  **Update `Info.plist`:** Remove Google Sign-In URL schemes and add any necessary OneDrive URL schemes or permissions.
3.  **Testing:** Thoroughly test OneDrive authentication, album selection/creation, photo fetching, and wallpaper updates.
