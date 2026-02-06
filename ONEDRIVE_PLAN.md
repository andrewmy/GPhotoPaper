# OneDrive Integration Battle Plan

This document outlines the plan to integrate OneDrive for photo management, targeting **personal Microsoft accounts** and using **Microsoft Graph Albums (bundles)** as the primary wallpaper source.

## Current status (repo)

- Repo is aligned to OneDrive (Google Sign-In removed).
- Core wallpaper pipeline exists (`WallpaperManager`) and settings UI exists.
- Implemented:
  - `OneDriveAuthService`: **MSAL** wrapper (interactive sign-in, silent token acquisition, sign-out).
  - `OneDrivePhotosService`: Microsoft Graph v1.0 for **albums (bundle albums)** (list albums, verify album, fetch photos in an album).
  - Settings UI: sign-in + **album** selection (+ link to manage albums in OneDrive Photos).
- CLI builds: `xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' ... build` succeeds when the environment has keychain/signing access.

### What works today (album mode)

- Sign in/out (MSAL) and silent token acquisition for scheduled wallpaper updates.
- List albums, select an album, and fetch image items from that album via Graph.
- Wallpaper update:
  - Downloads via `GET /me/drive/items/{item-id}/content` (authorized)
  - Does not rely on selecting `@microsoft.graph.downloadUrl` in `$select` (can 400 on some endpoints)
  - Applies filtering (min width, horizontal only) when image dimensions are available

### Configuration keys (current)

`Info.plist` currently expects:

- `OneDriveClientId`
- `OneDriveRedirectUri`
- `OneDriveScopes` (space-separated)
- Optional: `OneDriveAuthorityHost` (default `login.microsoftonline.com`), `OneDriveTenant` (default `common`)

## Decisions (locked in)

1. **Auth library:** MSAL (Microsoft Authentication Library).
  - Other providers may use AppAuth or other mechanism
2. **Wallpaper source:** OneDrive **Albums** (Graph “bundle album”) instead of folders.

## What “album” means in Graph

- Album is a **bundle**: a `driveItem` with `bundle.album` facet.
- Listing albums: `GET /drive/bundles?$filter=bundle/album ne null`
- Album contents: `GET /drive/items/{bundle-id}?expand=children` (page via `children@odata.nextLink`)
- Creating / modifying albums requires write scopes:
  - Create: `POST /drive/bundles` with `bundle: { album: {} }`
  - Add/remove item: `POST /drive/bundles/{id}/children` / `DELETE /drive/bundles/{id}/children/{item-id}`

Note: Bundle/album APIs are **personal Microsoft account** focused. If we later want to support work/school tenants, plan a fallback source mode (folder selection or in-app “virtual set”).

### Graph v1.0 quirk (personal accounts)

In practice (at least for some personal accounts), `bundle.album` is not reliably present and the `$filter=bundle/album ne null` query can return an empty list even when OneDrive Photos shows albums.

Current implementation uses the bundles endpoints and identifies “album-like” bundles using:

- `bundle.album` when present, OR
- `webUrl` host `photos.onedrive.com` (matches the OneDrive Photos album UI).

### Learnings / gotchas (Graph)

- Some Graph responses expose `@microsoft.graph.downloadUrl`, but selecting it via `$select` can fail with HTTP 400 (“AnnotationSegment”). Prefer downloading the chosen item using `/content`.
- For DriveItem `children` expansion, Graph supports only `$select` and `$expand` inside the `$expand` options. Using `$top` inside `children(...)` can fail with HTTP 400 (“Can only provide expand and select for expand options”).
- For bundle albums, `GET /me/drive/items/{id}/children` can be unreliable; prefer `GET /me/drive/items/{id}?$expand=children(...)` (and page using `children@odata.nextLink`).

## Remaining work (phased)

### Phase 1 — Switch auth to MSAL (done)

- Add MSAL dependency (SwiftPM).
- Implement `OneDriveAuthService` as an MSAL wrapper:
  - Interactive sign-in + sign-out
  - Silent token acquisition for scheduled wallpaper updates
  - Multiple accounts: decide whether to support now or later (MSAL makes this easier).
- Update configuration:
  - Redirect URI uses `msauth.<bundle_id>://auth` (Azure portal iOS/macOS platform).
  - Local dev client id via `GPhotoPaper/Secrets.xcconfig` (gitignored) → `ONEDRIVE_CLIENT_ID` → `OneDriveClientId` in `Info.plist`.
  - Avoid passing reserved OIDC scopes to MSAL acquire-token calls (`openid`, `profile`, `offline_access`).
- Keychain entitlement (macOS):
  - Ensure `keychain-access-groups` includes `$(AppIdentifierPrefix)com.microsoft.identity.universalstorage` (MSAL default cache group), otherwise you may hit OSStatus `-34018`.
- Cleanup (later):
  - Remove the native `ASWebAuthenticationSession` + PKCE fallback once MSAL is stable.

### Phase 2 — Albums API (Graph bundles) (done)

- Update the service layer:
  - Add `listAlbums()`, `verifyAlbumExists(albumId:)`, `searchPhotos(in albumId:)` (album contents).
- Update models:
  - Rename settings from folder to album: `selectedAlbumId`, `selectedAlbumName`, `selectedAlbumWebUrl`.
  - Ensure picture metadata is captured (`width/height`) to support filtering in `WallpaperManager`.
- Scopes:
  - Start: `User.Read Files.Read` (MSAL handles OIDC reserved scopes like `offline_access` automatically)
  - Add later if needed: `Files.ReadWrite` (create album / add items).

### Phase 3 — UI update (albums instead of folders) (done)

- Album picker (done):
  - “Load albums” → list bundles
  - Selection persisted in settings
  - Link to open the selected album (when `webUrl` is available from bundle metadata)
  - Link to manage albums in OneDrive Photos
- Startup behavior / validation:
  - On app start, verify the previously selected album still exists and is accessible.
  - When loading a stored selection, probe the first page and show a warning if there are no usable photos.
  - Auto-load albums on startup when signed in (so the picker appears without manual reload).
  - Keep manual ID entry + full scan behind “Advanced”.

### Phase 4 — Offline mode (planned)

Goal: a workable experience when Graph is temporarily unavailable.

- Cache a “last known good” wallpaper image (and possibly a small ring buffer).
- If a wallpaper update fails (offline, token issue, Graph errors), fall back to cached images instead of failing silently.
- UX: surface an “offline / last updated” status and guidance to re-auth / retry.

### Phase 5 — Album write operations (planned; separate)

- Create album UI (requires `Files.ReadWrite`)
- Add/remove items from an album within the app (also `Files.ReadWrite`) to support curation without leaving the app

### Phase 6 — Wallpaper suitability filtering (planned)

Goal: prefer images that will look good as wallpaper on the current Mac (and later, multiple displays).

- Minimum resolution:
  - Prefer images with pixel dimensions >= current screen pixel size (account for Retina scaling).
  - Decide behavior when width/height metadata is missing: allow, deprioritize, or download headers to detect dimensions.
- Orientation and aspect ratio:
  - Keep “horizontal only” option, but consider aspect-ratio bounds (avoid extreme panoramas unless user opts in).
  - Optionally match aspect ratio to the current screen more closely (especially for Fill vs Fit).
- File format / type:
  - Exclude videos and non-image mime types.
  - Decide whether to accept formats like HEIC, PNG, GIF (animated), and how to handle alpha/animation.
- Quality / UX heuristics (optional):
  - Avoid duplicates (same item id) and repeat too frequently.
  - Prefer recent photos or favorites (if Graph metadata supports it later).

### Phase 7 — Testing & hardening

- Unit tests:
  - Token handling boundaries (signed out, expired token) via mocks.
  - Album paging and filtering logic.
- UX checks:
  - Error messaging for “not configured” vs “not signed in” vs “no albums/photos”.
  - Behavior when album disappears or loses permissions.
- Multi-monitor support (later): decide per-screen vs all screens.

## Cleanup checklist

- Remove folder-centric UI/strings once albums are the default. (done)
- Remove native OAuth implementation once MSAL is fully wired.
- Ensure `Info.plist` contains only the final OAuth callback configuration and documented keys.
