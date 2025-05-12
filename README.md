<div align="center">
<img src="assets/rateme.png" width="200" align="center">

# Rate Me!

![Version](https://img.shields.io/github/v/release/ALi3naTEd0/RateMe?include_prereleases)
![License](https://img.shields.io/badge/license-MIT-green)
![Downloads](https://img.shields.io/github/downloads/ALi3naTEd0/RateMe/total)
![Last Commit](https://img.shields.io/github/last-commit/ALi3naTEd0/RateMe)
![Stars](https://img.shields.io/github/stars/ALi3naTEd0/RateMe)

<a href="https://discord.gg/kFGQckFz">
  <img src="https://img.shields.io/badge/Discord-Join%20Chat-5865F2?style=flat&logo=discord&logoColor=white" alt="Discord Server">
</a>

</div>

<div align="center">

[Introduction](#introduction) •
[Features](#features) •
[Screenshots](#screenshots) •
[Getting Started](#getting-started) •
[Downloads](#downloads) •
[Installation](#installation) •
[Technologies](#technologies-used) •
[Project Architecture](#project-architecture) •
[Development](#development) •
[Roadmap](#roadmap) •
[Contributing](#contributions) •
[License](#license) •
[Acknowledgements](#acknowledgements) •
[Contact](#contact) •
[Documentation](#documentation)

</div>

## Introduction

Welcome to **Rate Me!**, an app designed for music lovers to discover, rate, and manage your favorite albums effortlessly. With **Rate Me!**, you can explore a wide variety of albums, rate each song individually, and get an overall view of the album's quality based on your personal ratings.

## Features

### Core Features
- **Multi-Platform Support**: Rate albums from Apple Music, Spotify, Deezer, Discogs, and Bandcamp
- **Track-by-Track Rating**: Rate individual tracks on a 0-10 scale
- **Custom Lists**: Organize albums into custom lists (e.g., "Best of 2023", "Prog Rock", etc.)
- **Album Notes**: Save personal reviews, thoughts, and observations for each album
- **Data Export/Import**: Easily backup and restore your collection
- **Share as Images**: Generate beautiful images of your ratings to share on social media
- **Offline Support**: Access your saved albums and ratings without an internet connection
- **SQLite Database**: Fast performance and reliable data storage
- **Track Duration Support**: View track lengths from various platforms including Discogs

### Platform Integration
- **Cross-Platform Matching**: Easily find your albums across different music services
- **API Key Support**: Secure user-provided API keys for Spotify and Discogs services
- **Clipboard Detection**: Automatically detects music platform URLs from clipboard
- **Cross-Platform Streaming**: Buttons for Spotify, Apple Music and Deezer with context menu options
- **Universal EP/Single Handling**: Consistent album format detection across all platforms

### User Interface
- **Dark Mode**: Choose between light, dark, or system themes
- **Custom Colors**: Personalize the app with your preferred color scheme
- **Pull-to-Refresh**: Update content with a simple swipe down gesture
- **Skeleton UI**: Beautiful loading placeholders while fetching content
- **Drag and Drop List Management**: Reorder custom lists and saved albums with intuitive controls

## Screenshots

| | | |
|:-------------------------:|:-------------------------:|:-------------------------:|
|![Screenshot 1](https://i.imgur.com/jjclzhS.png)       |  ![Screenshot 2](https://i.imgur.com/m73eQXI.png)|![Screenshot 3](https://i.imgur.com/ve8LkiB.png)|

## Getting Started

1. **Search for Albums**: Enter an artist or album name to search, or paste a URL from Apple Music, Bandcamp, Spotify, Deezer or Discogs
2. **Rate Albums**: Open an album and use the sliders to rate each track from 0-10
3. **Create Lists**: Organize your music by creating custom lists
4. **Add Album Notes**: Write personal reviews or observations about each album
5. **Share Your Ratings**: Generate beautiful images of your ratings to share

## Downloads

<div align="center">

### Desktop Applications

| Platform | Format | Download |
|:--------:|:------:|:--------:|
| Windows | Installer | [**RateMe_1.1.2-1.exe**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1.exe) |
| Windows | Portable | [**RateMe_1.1.2-1_portable.zip**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1_portable.zip) |
| macOS | Universal | [**RateMe_1.1.2-1.dmg**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1.dmg) |

### Linux Packages

| Format | Architecture | Download |
|:------:|:-----------:|:--------:|
| AppImage | x86_64 | [**RateMe_1.1.2-1.AppImage**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1.AppImage) |
| DEB | amd64 | [**RateMe_1.1.2-1_amd64.deb**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1_amd64.deb) |
| RPM | x86_64 | [**RateMe_1.1.2-1_x86_64.rpm**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1_x86_64.rpm) |
| Flatpak | Universal | [**RateMe_1.1.2-1.flatpak**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1.flatpak) |
| Arch Linux | - | [**AUR Instructions**](#arch-linux) |

### Mobile Applications

| Platform | Version | Download |
|:--------:|:-------:|:--------:|
| Android | Universal | [**RateMe_1.1.2-1.apk**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1.apk) |
| Android | arm64-v8a | [**RateMe_1.1.2-1_arm64-v8a.apk**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1_arm64-v8a.apk) |
| Android | armeabi-v7a | [**RateMe_1.1.2-1_armeabi-v7a.apk**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1_armeabi-v7a.apk) |
| Android | x86_64 | [**RateMe_1.1.2-1_x86_64.apk**](../../releases/download/v1.1.2-1/RateMe_1.1.2-1_x86_64.apk) |

</div>

## Installation

### Windows
1. Installer: Run `RateMe_1.1.2-1.exe` and follow the installation wizard
   - Or -
2. Portable: Extract `RateMe_1.1.2-1_portable.zip` and run `RateMe.exe`

### Android
1. Choose the correct version:
   - APK-Universal: Works on most devices
   - APK-arm64-v8a: Modern phones (2017+)
   - APK-armeabi-v7a: Older phones
   - APK-x86_64: Some tablets/ChromeOS

2. Install:
   - Download the chosen APK
   - If "Install from unknown sources" appears:
     1. Go to Settings > Security
     2. Enable "Unknown sources" or
     3. Allow "Install unknown apps" for your browser
   - Open the downloaded APK and follow the steps

Note: If you're not sure which version to use, install APK-Universal

### macOS
1. Download `RateMe_1.1.2-1.dmg`
2. Open the DMG file
3. Drag RateMe to your Applications folder
4. First time running:
   - Right-click (or Control+click) on RateMe in Applications
   - Select "Open" from the menu
   - If blocked, go to System Settings -> Privacy & Security
   - Scroll down and click "Open Anyway" next to RateMe
   - Click "Open" on the final security dialog

Note: If you see "app is damaged" message, open Terminal and run:
```bash
xattr -cr /Applications/RateMe.app
```
Then try opening the app again. This removes macOS security quarantine.

### Linux Installation

#### AppImage
1. Download `RateMe_1.1.2-1.AppImage`
2. Make it executable:
```bash
chmod +x RateMe_1.1.2-1.AppImage
```
3. Run it:
```bash
./RateMe_1.1.2-1.AppImage
```
No installation needed - the AppImage is portable and works on most Linux distributions.

#### DEB Package (Ubuntu/Debian)
```bash
sudo apt install ./RateMe_1.1.2-1_amd64.deb
```

#### RPM Package (Fedora/RHEL)
```bash
sudo dnf install ./RateMe_1.1.2-1_x86_64.rpm
```

#### Flatpak Installation

1. Download the Flatpak package from [releases](../../releases/download/v1.1.2-1/RateMe_1.1.2-1.flatpak)

2. Install required runtime (if not already installed):
```bash
flatpak install flathub org.freedesktop.Platform//21.08
```

3. Install RateMe:
```bash
flatpak install ./RateMe_1.1.2-1.flatpak
```

4. Run RateMe:
```bash
flatpak run com.example.RateMe
```

##### Uninstallation

```bash
flatpak uninstall com.example.RateMe
```

#### Arch Linux
```bash
git clone https://github.com/ALi3naTEd0/RateMe.git
cd RateMe
makepkg -si
```

## Technologies Used

- [Flutter](https://flutter.dev/): Used for developing the user interface, Flutter provides a flexible and intuitive framework for creating visually appealing applications.
- [Dart](https://dart.dev/): As the primary programming language, Dart powers the logic and functionality of the **Rate Me!** application.
- [SQLite](https://www.sqlite.org/): Local database for efficient album and track storage.
- [iTunes API](https://affiliate.itunes.apple.com/resources/documentation/itunes-store-web-service-search-api/): Utilized to search for albums and retrieve detailed album data.
- [Spotify API](https://developer.spotify.com/documentation/web-api/): Integration for searching and retrieving Spotify albums and tracks.
- [Deezer API](https://developers.deezer.com/api): Music streaming platform API for album and track discovery.
- [Discogs API](https://www.discogs.com/developers/): Deep integration with Discogs for comprehensive album and track information.
- **JSON Parser for Bandcamp**: A JSON parser is used to search and retrieve detailed album data from Bandcamp links.

## Getting Started

1. **Search for Albums**: Enter an artist or album name to search, or paste a URL from Apple Music, Bandcamp, Spotify, Deezer or Discogs
2. **Rate Albums**: Open an album and use the sliders to rate each track from 0-10
3. **Create Lists**: Organize your music by creating custom lists
4. **Add Album Notes**: Write personal reviews or observations about each album
5. **Share Your Ratings**: Generate beautiful images of your ratings to share

## Data Management

RateMe provides several options for managing your data:

- **Standard Backup**: Export/import your entire collection with ratings, custom lists, and notes
- **Album Exchange**: Share individual albums with friends who use RateMe
- **Date Fixing Utility**: Batch fix missing or incorrect album release dates
- **Platform Match Cleaner**: Fix incorrect associations between albums on different platforms
- **Database Optimization**: Vacuum and analyze database for improved performance
- **Database Integrity**: Check and repair potential issues with album data
- **Database Migration**: Seamless upgrade from older versions with progress tracking
- **Track Management**: Fix duplicate tracks and refresh missing track information

## Supported Platforms

- Android
- Windows
- macOS
- Linux

## About The Unified Data Model

RateMe uses a unified data model that ensures consistent handling of music from different platforms. This model:

- Works across multiple music platforms (Apple Music, Spotify, Deezer, Discogs, and Bandcamp)
- Maintains backward compatibility with previous versions
- Provides consistent field naming and data access
- Standardizes album data format between different music platforms
- Normalizes album name variations (EP, Single, etc.) across platforms
- Improves reliability and error handling
- Supports cascading deletes and proper relationships
- Enables cross-platform album matching and lookup

## Privacy

RateMe respects your privacy:
- All data is stored locally on your device
- No personal information is collected or transmitted
- No tracking or analytics
- API keys are securely stored in the local database

## Project Architecture

This Flutter project follows a clean architecture pattern with clear separation of concerns. The main components are described below:

```
/home/x/RateMe/lib/
├── core/                           # Core layer (domain & application logic)
│   ├── api/
│   │   └── api_keys.dart           # API key management abstraction
│   ├── models/
│   │   └── album_model.dart        # Domain entities and models
│   ├── services/
│   │   ├── logging.dart            # Application-wide logging service
│   │   ├── search_service.dart     # Search functionality across platforms 
│   │   ├── theme_service.dart      # Theme management
│   │   └── user_data.dart          # Repository-like service for user data
│   └── utils/
│       ├── clipboard_detector.dart # URL detection from clipboard
│       ├── color_utility.dart      # Color conversion and manipulation
│       ├── date_fixer_utility.dart # Date standardization
│       └── version_info.dart       # App version tracking
│
├── database/                       # Data persistence layer
│   ├── api_key_manager.dart        # API credentials storage
│   ├── backup_converter.dart       # Import/export functionality
│   ├── cleanup_utility.dart        # Database maintenance
│   ├── database_helper.dart        # SQLite abstraction
│   ├── data_migration_service.dart # Data migration utilities
│   ├── json_fixer.dart            # JSON repair tools
│   ├── migration_utility.dart      # Schema migration
│   ├── preferences_migration.dart  # Settings migration
│   ├── search_history_db.dart      # Search history storage
│   └── track_recovery_utility.dart # Track data recovery
│
├── features/                       # Feature modules
│   ├── albums/
│   │   ├── details_page.dart       # Album details screen
│   │   ├── saved_album_page.dart   # Saved album view
│   │   └── saved_ratings_page.dart # Album collection view
│   ├── custom_lists/
│   │   └── custom_lists_page.dart  # Custom collection management
│   ├── notifications/
│   │   └── global_notifications.dart # App-wide messaging
│   ├── platforms/
│   │   ├── model_mapping_service.dart # Platform data normalization
│   │   ├── platform_data_analyzer.dart # Platform data analysis
│   │   ├── platform_service.dart   # Platform service abstractions
│   │   └── platform_ui.dart        # Platform-specific UI
│   ├── preload/
│   │   └── preload_service.dart    # Resource preloading
│   ├── search/
│   │   └── platform_match_widget.dart # Cross-platform matching UI
│   └── settings/
│       ├── migration_util.dart      # Settings migration utility
│       ├── settings_page.dart       # App settings UI
│       └── settings_service.dart    # Settings management
│
├── navigation/                      # Navigation layer
│   └── navigation_util.dart         # Navigation service
│
├── platforms/                       # Platform integrations
│   ├── middleware/
│   │   ├── deezer_middleware.dart   # Deezer data enhancement
│   │   └── discogs_middleware.dart  # Discogs data enhancement
│   ├── apple_music_service.dart     # Apple Music integration
│   ├── bandcamp_service.dart        # Bandcamp integration
│   ├── deezer_service.dart          # Deezer integration
│   ├── discogs_service.dart         # Discogs integration
│   ├── platform_service_base.dart   # Base service class
│   ├── platform_service_factory.dart # Service provider
│   └── spotify_service.dart         # Spotify integration
│
├── ui/                              # UI layer
│   ├── themes/
│   │   └── color_reset_utility.dart # Theme color management
│   └── widgets/
│       ├── footer.dart              # App footer with version info
│       ├── platform_match_cleaner.dart # Platform match fixing UI
│       ├── share_widget.dart        # Rating sharing functionality
│       └── skeleton_loading.dart    # Loading UI placeholders
│
└── main.dart                        # Application entry point
```

### Architecture Benefits

The clean architecture provides several key advantages:

1. **Separation of Concerns**: Each layer has distinct responsibilities, making the codebase more organized and maintainable
2. **Testability**: Core business logic is isolated from external dependencies for easier testing
3. **Modularity**: Features are encapsulated in their own modules for better code organization
4. **Scalability**: Easy to add new features without disrupting existing functionality
5. **Dependency Management**: Clear flow of dependencies from outer layers inward

### Main Components

1. **Core Application**
   - **Main**: Entry point and root widget handling theme state
   - **ThemeService**: Centralized theme management with reactive updates
   - **GlobalNotifications**: App-wide messaging system
   - **Footer**: Consistent layout component with version info and links
   - **NavigationUtil**: Page navigation and route handling utility

2. **Data Models**
   - **AlbumModel**: Core data model for albums, tracks, and unified platform handling
   - **UserData**: High-level data operations and persistence 
   - **ApiKeyManager**: Secure credentials storage and validation
   - **ModelMappingService**: Data conversion between different format models

3. **User Interface**
   - **SearchPage**: Album search interface with platform integration
   - **DetailsPage**: Album details and rating interface
   - **SavedAlbumPage**: Individual saved album view and editing
   - **SavedRatingsPage**: Album list management and ratings display
   - **CustomListsPage**: Custom collections management
   - **SettingsPage**: Application configuration and preferences

4. **UI Components**
   - **PlatformMatchWidget**: Cross-platform streaming service integration buttons
   - **ShareWidget**: Album rating image generation for social sharing
   - **SkeletonLoading**: Loading state placeholders for UI elements
   - **PlatformMatchCleaner**: Interface for fixing incorrect platform associations

5. **Database Layer**
   - **DatabaseHelper**: Central SQLite database interaction
   - **MigrationUtility**: Database and model version upgrades
   - **BackupConverter**: Data import/export and format conversion
   - **SearchHistoryDb**: Search history tracking and management

6. **Platform Services**
   - **PlatformServiceFactory**: Service provider for multiple music platforms
   - **PlatformMiddleware**: Enhanced album data processing (Discogs, Deezer)
   - **SearchService**: Cross-platform search operations
   - **PlatformUI**: Platform-specific UI elements and styling
   - **PreloadService**: Resource and data preparation utility

7. **Utilities**
   - **Logging**: Diagnostic and error tracking
   - **ColorUtility**: Color management and conversion tools
   - **DateFixerUtility**: Album date corrections and standardization
   - **ClipboardDetector**: URL detection and processing
   - **JsonFixer**: JSON data structure normalization and repair
   - **DebugUtil**: Development debugging tools
   - **CleanupUtility**: Database and resource maintenance

## Development

- **Environment Setup**: 
  1. Ensure you have Flutter installed and added to your PATH. If not, follow the [official Flutter installation guide](https://flutter.dev/docs/get-started/install).
  2. Once Flutter is set up, follow the steps in the [Getting Started](#getting-started) section above to set up the project.

- **Code Conventions**: 
  We follow the official [Dart style guide](https://dart.dev/guides/language/effective-dart/style) and [Flutter style guide](https://github.com/flutter/flutter/wiki/Style-guide-for-Flutter-repo). Please ensure your contributions adhere to these guidelines.

- **Building the App**:
  Run the following commands to build the app for your target platform:
  ```bash
  flutter pub get
  flutter build <platform>
  ```
  Where `<platform>` can be `apk`, `windows`, `macos`, or `linux`.

## Roadmap

- Advanced search filter options
- Search history implementation and management
- Advanced query optimization for large datasets (10,000+ albums)
- Database telemetry and performance monitoring
- Album notes export and import functionality
- Bulk editing tools for ratings and album data
- Custom tags for albums and tracks
- Local music file integration
- Statistics and listening insights
- Cross-device sync via private cloud storage
- Rating trends and history visualization
- iOS version (pending Apple Developer subscription)

## Contributions

Contributions to the project are welcome! If you encounter any issues or wish to request a new feature, feel free to inform us through GitHub issues.

To contribute:
1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the `LICENSE` file for details.

The MIT License is a permissive license that is short and to the point. It allows people to do anything with your code with proper attribution and without warranty.

## Acknowledgements

- [http](https://pub.dev/packages/http) - HTTP requests and API integration
- [shared_preferences](https://pub.dev/packages/shared_preferences) - Local data storage
- [sqflite](https://pub.dev/packages/sqflite) - SQLite database support
- [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) - SQLite FFI implementation for desktop platforms
- [html](https://pub.dev/packages/html) - HTML parsing for structured data
- [url_launcher](https://pub.dev/packages/url_launcher) - External URL handling
- [intl](https://pub.dev/packages/intl) - Date formatting
- [path_provider](https://pub.dev/packages/path_provider) - File system access
- [file_picker](https://pub.dev/packages/file_picker) - File selection dialogs
- [share_plus](https://pub.dev/packages/share_plus) - Content sharing
- [package_info_plus](https://pub.dev/packages/package_info_plus) - App version info
- [flutter_svg](https://pub.dev/packages/flutter_svg) - SVG rendering for platform icons
- [logging](https://pub.dev/packages/logging) - Application logging
- [flex_color_picker](https://pub.dev/packages/flex_color_picker) - Color selection utilities
- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) - App icon generation
- [path](https://pub.dev/packages/path) - File path manipulation
- [flutter_lints](https://pub.dev/packages/flutter_lints) - Lint rules for clean code
- [flutter_distributor](https://pub.dev/packages/flutter_distributor) - App distribution helpers
- [build_runner](https://pub.dev/packages/build_runner) - Build system for code generation
- [json_serializable](https://pub.dev/packages/json_serializable) - JSON serialization utilities

## Contact

[Discord](https://discord.gg/kFGQckFz)

Project Link: [https://github.com/ALi3naTEd0/RateMe](https://github.com/ALi3naTEd0/RateMe)

## Documentation
- [Changelog](CHANGELOG.md)

---
Developed with ♥ by [ALi3naTEd0](https://github.com/ALi3naTEd0)
