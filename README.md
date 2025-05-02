<div align="center">
<img src="assets/rateme.png" width="200" align="center">

# Rate Me!

![Version](https://img.shields.io/github/v/release/ALi3naTEd0/RateMe?include_prereleases)
![License](https://img.shields.io/badge/license-MIT-green)
![Downloads](https://img.shields.io/github/downloads/ALi3naTEd0/RateMe/total)
![Last Commit](https://img.shields.io/github/last-commit/ALi3naTEd0/RateMe)
![Stars](https://img.shields.io/github/stars/ALi3naTEd0/RateMe)

</div>

<div align="center">

[Introduction](#introduction) •
[Features](#features) •
[Screenshots](#screenshots) •
[Downloads](#downloads) •
[Installation](#installation) •
[Technologies](#technologies-used) •
[Getting Started](#getting-started) •
[How to Use](#how-to-use) •
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

- **Multi-Platform Support**: Rate albums from Apple Music, Spotify, Deezer, Discogs, and Bandcamp
- **Cross-Platform Matching**: Easily find your albums across different music services
- **Track-by-Track Rating**: Rate individual tracks on a 0-10 scale
- **Custom Lists**: Organize albums into custom lists (e.g., "Best of 2023", "Prog Rock", etc.)
- **Data Export/Import**: Easily backup and restore your collection
- **Share as Images**: Generate beautiful images of your ratings to share on social media
- **Clipboard Detection**: Automatically detects music platform URLs from clipboard
- **Unified Data Model**: Compatible data structure across different music platforms
- **Dark Mode**: Choose between light, dark, or system themes
- **Custom Colors**: Personalize the app with your preferred color scheme
- **Offline Support**: Access your saved albums and ratings without an internet connection
- **One-Touch Import/Export**: Quickly import/export individual albums or your entire collection
- **Pull-to-Refresh**: Update content with a simple swipe down gesture
- **Skeleton UI**: Beautiful loading placeholders while fetching content
- **Pagination**: Smooth navigation through large collections
- **Search History**: Access your recent album searches
- **SQLite Database**: Fast performance and reliable data storage
- **Track Duration Support**: View track lengths from various platforms including Discogs

## Screenshots

| | | |
|:-------------------------:|:-------------------------:|:-------------------------:|
|![Screenshot 1](https://i.imgur.com/jjclzhS.png)       |  ![Screenshot 2](https://i.imgur.com/m73eQXI.png)|![Screenshot 3](https://i.imgur.com/ve8LkiB.png)|

## Downloads

<div align="center">

### Desktop Applications

| Platform | Format | Download |
|:--------:|:------:|:--------:|
| Windows | Installer | [**RateMe_1.1.0-4.exe**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4.exe) |
| Windows | Portable | [**RateMe_1.1.0-4_portable.zip**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4_portable.zip) |
| macOS | Universal | [**RateMe_1.1.0-4.dmg**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4.dmg) |

### Linux Packages

| Format | Architecture | Download |
|:------:|:-----------:|:--------:|
| AppImage | x86_64 | [**RateMe_1.1.0-4.AppImage**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4.AppImage) |
| DEB | amd64 | [**RateMe_1.1.0-4_amd64.deb**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4_amd64.deb) |
| RPM | x86_64 | [**RateMe_1.1.0-4_x86_64.rpm**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4_x86_64.rpm) |
| Flatpak | Universal | [**RateMe_1.1.0-4.flatpak**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4.flatpak) |
| Arch Linux | - | [**AUR Instructions**](#arch-linux) |

### Mobile Applications

| Platform | Version | Download |
|:--------:|:-------:|:--------:|
| Android | Universal | [**RateMe_1.1.0-4.apk**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4.apk) |
| Android | arm64-v8a | [**RateMe_1.1.0-4_arm64-v8a.apk**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4_arm64-v8a.apk) |
| Android | armeabi-v7a | [**RateMe_1.1.0-4_armeabi-v7a.apk**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4_armeabi-v7a.apk) |
| Android | x86_64 | [**RateMe_1.1.0-4_x86_64.apk**](../../releases/download/v1.1.0-4/RateMe_1.1.0-4_x86_64.apk) |
| iOS | - | Coming soon |

</div>

## Installation

### Windows
1. Installer: Run `RateMe_1.1.0-4.exe` and follow the installation wizard
   - Or -
2. Portable: Extract `RateMe_1.1.0-4_portable.zip` and run `RateMe.exe`

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
1. Download `RateMe_1.1.0-4.dmg`
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
1. Download `RateMe_1.1.0-4.AppImage`
2. Make it executable:
```bash
chmod +x RateMe_1.1.0-4.AppImage
```
3. Run it:
```bash
./RateMe_1.1.0-4.AppImage
```
No installation needed - the AppImage is portable and works on most Linux distributions.

#### DEB Package (Ubuntu/Debian)
```bash
sudo apt install ./RateMe_1.1.0-4_amd64.deb
```

#### RPM Package (Fedora/RHEL)
```bash
sudo dnf install ./RateMe_1.1.0-4_x86_64.rpm
```

#### Flatpak Installation

1. Download the Flatpak package from [releases](../../releases/download/v1.1.0-4/RateMe_1.1.0-4.flatpak)

2. Install required runtime (if not already installed):
```bash
flatpak install flathub org.freedesktop.Platform//21.08
```

3. Install RateMe:
```bash
flatpak install ./RateMe_1.1.0-4.flatpak
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
4. **Share Your Ratings**: Generate beautiful images of your ratings to share

## Data Management

RateMe provides several options for managing your data:

- **Standard Backup**: Export/import your entire collection with ratings and custom lists
- **Album Exchange**: Share individual albums with friends who use RateMe
- **Data Conversion**: Convert from older versions of RateMe to the new unified format
- **Repair Tools**: Fix potential issues with album data
- **Database Migration**: Seamless upgrade to new database format for better performance

## Supported Platforms

- iOS
- Android
- Windows
- MacOS
- Linux

## About The Unified Data Model

RateMe uses a unified data model that ensures consistent handling of music from different platforms. This model:

- Works across multiple music platforms (Apple Music, Spotify, Deezer, Discogs, and Bandcamp)
- Maintains backward compatibility with previous versions
- Provides consistent field naming and data access
- Improves reliability and error handling
- Supports cascading deletes and proper relationships
- Enables cross-platform album matching and lookup

## Privacy

RateMe respects your privacy:
- All data is stored locally on your device
- No personal information is collected or transmitted
- No tracking or analytics

## Project Architecture

This Flutter project follows a modular architecture and uses the Provider pattern for state management. The main components are described below:

### Main Components

1. **MusicRatingApp**: Main widget handling theme state and persistence
2. **SearchPage**: Album search interface with platform integration
3. **SavedRatingsPage**: Album list management and ratings display
4. **CustomListsPage**: Custom collections management
5. **DetailsPage**: Album details and rating interface
6. **UserData**: Data persistence and management utility
7. **PlatformService**: Handles interactions with different music platforms
8. **PlatformUI**: Platform-specific UI elements and styling

### Data Handling

- **SQLite Database**: Efficient local storage for albums, ratings, and preferences
- **Migration Utility**: Tools for upgrading data between versions
- **HTTP**: API requests to music platforms
- **HTML**: Extraction of structured data from web pages

### External Integrations

- **iTunes API**: Album and track information via official API
- **Spotify API**: OAuth2 integration for fetching album and track details
- **Deezer API**: Direct integration for album and track details
- **Discogs API**: Comprehensive integration with release matching and master record support
- **Bandcamp**: Album and track information via embedded JSON-LD data
- **RateYourMusic**: Additional album information lookup

## Development

- **Environment Setup**: 
  1. Ensure you have Flutter installed and added to your PATH. If not, follow the [official Flutter installation guide](https://flutter.dev/docs/get-started/install).
  2. Once Flutter is set up, follow the steps in the [Getting Started](#getting-started) section above to set up the project.

- **Code Conventions**: 
  We follow the official [Dart style guide](https://dart.dev/guides/language/effective-dart/style) and [Flutter style guide](https://github.com/flutter/flutter/wiki/Style-guide-for-Flutter-repo). Please ensure your contributions adhere to these guidelines.

- **Running Tests**: 
  To run tests, use the following command in the project root directory:

## Roadmap

- Improved Discogs integration with more metadata support
- Implementation of Apple Music authentication and API integration
- Advanced search filter and sort options
- Advanced query optimization for large datasets (10,000+ albums)
- Database telemetry and performance monitoring
- Full Spotify OAuth2 implementation
- Integration with additional music streaming services
- Functionality to share ratings on RateYourMusic.com

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
- [html](https://pub.dev/packages/html) - HTML parsing for structured data
- [url_launcher](https://pub.dev/packages/url_launcher) - External URL handling
- [intl](https://pub.dev/packages/intl) - Date formatting
- [path_provider](https://pub.dev/packages/path_provider) - File system access
- [file_picker](https://pub.dev/packages/file_picker) - File selection dialogs
- [share_plus](https://pub.dev/packages/share_plus) - Content sharing
- [package_info_plus](https://pub.dev/packages/package_info_plus) - App version info
- [flutter_svg](https://pub.dev/packages/flutter_svg) - SVG rendering for platform icons
- [logging](https://pub.dev/packages/logging) - Application logging

## Contact

[Discord](https://discord.gg/UQ55AVv4ZY)

Project Link: [https://github.com/ALi3naTEd0/RateMe](https://github.com/ALi3naTEd0/RateMe)

## Documentation
- [Changelog](CHANGELOG.md)

---
Developed with ♥ by [X](https://github.com/ALi3naTEd0)
