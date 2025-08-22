# GPhotoPaper Development Checklist

This document outlines the remaining tasks for the GPhotoPaper macOS application, now pivoting to OneDrive for photo management.

## Core Features

- [ ] **Authentication**
  - [ ] Implement OneDrive OAuth 2.0 authentication.
  - [ ] Sign in to a OneDrive account.
  - [ ] Sign out from a OneDrive account.

- [ ] **OneDrive Album Management**
  - [ ] Implement logic to list user's OneDrive albums/folders.
  - [ ] Implement UI for user to select an existing OneDrive album/folder.
  - [ ] Implement logic to create a new OneDrive album/folder if user chooses.
  - [ ] Persist the ID and name of the selected OneDrive album/folder using `UserDefaults`.
  - [ ] On app start, check that the selected OneDrive album/folder is still available.
  - [ ] On retrieving the stored album/folder, check picture count.
  - [ ] If there are no pictures, show a warning.
  - [ ] Add a link to quickly access the selected OneDrive album/folder wherever it is mentioned.

- [x] **Settings User Interface (UI)**
  - [x] Display UI for "Create/Manage App Album". (Will be updated for OneDrive)
  - [x] Implement UI for choosing picture change frequency ("Never", "Every Hour", "Every 6 Hours", "Daily").
  - [x] Implement UI for choosing to pick the next picture randomly or in time sequence.
  - [x] Implement UI for choosing minimum picture width (default to desktop resolution).
  - [x] Implement UI for choosing wallpaper fill mode ("Fill", "Fit", "Stretch", "Center").
  - [x] Implement a button to change the wallpaper immediately.
  - [x] Refresh picture count on "Change Wallpaper Now" button click.

- [ ] **Core Wallpaper Functionality**
  - [ ] Implement logic to fetch photos from the selected OneDrive album/folder.
  - [x] Implement logic to filter photos by minimum width.
  - [x] Implement logic to filter photos by aspect ratio (horizontal only).
  - [x] Implement logic to pick the next picture randomly or in time sequence.
  - [x] Implement logic to set the current wallpaper using `NSWorkspace`.
  - [x] Implement scheduling for automatic wallpaper changes based on frequency.

## Project Setup & Maintenance

- [x] Project opens and builds in Xcode.
- [x] Project uses Swift and SwiftUI.
- [x] Project builds via `xcodebuild` command line.
- [x] `Info.plist` correctly configured for URL schemes.
- [x] Keychain Sharing capability enabled.
- [x] App Sandbox capability enabled.
- [x] Create a comprehensive GitHub-friendly `README.md` file for humans. Include instructions on how to build and run the project, and what to do manually in the console or Xcode, and values to change in the code.