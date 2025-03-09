<img src="assets/rateme.png" width="200" align="center">

# Rate Me!

![Version](https://img.shields.io/github/v/release/ALi3naTEd0/RateMe?include_prereleases)
![License](https://img.shields.io/badge/license-MIT-green)
![Downloads](https://img.shields.io/github/downloads/ALi3naTEd0/RateMe/total)
![Last Commit](https://img.shields.io/github/last-commit/ALi3naTEd0/RateMe)
![Stars](https://img.shields.io/github/stars/ALi3naTEd0/RateMe)

[Discord](https://discord.gg/UQ55AVv4ZY)

<div align="center">

[Introduction](#introduction) •
[Features](#features) •
[Screenshots](#screenshots) •
[Downloads](#downloads) •
[Installation](#installation) •
[Documentation](#documentation) •
[Development](#development) •
[Contributing](#contributions)

</div>

## Introduction

Welcome to **Rate Me!**, an app designed for music lovers to discover, rate, and manage your favorite albums effortlessly. With **Rate Me!**, you can explore a wide variety of albums, rate each song individually, and get an overall view of the album's quality based on your personal ratings.

## Features

- 🎵 **Album Search**: Search iTunes or paste Bandcamp URLs to find albums
- ⭐ **Rating System**: Rate individual tracks from 0 to 10
- 📊 **Statistics**: View average ratings and album statistics
- 📱 **Multi-platform Support**: Works on Android, Windows, Linux and macOS
- 🎨 **Dark/Light Theme**: Toggle between light and dark modes
- 📁 **Custom Lists**: Create and manage custom album collections
- 📷 **Share Images**: Generate and share album ratings as images
- 💾 **Data Management**:
  - Import/Export complete data backups
  - Import/Export individual album data
  - Backup data in JSON format
- 🌐 **External Integration**: Quick access to RateYourMusic for additional info

## Screenshots

| | | |
|:-------------------------:|:-------------------------:|:-------------------------:|
|![Screenshot 1](https://i.imgur.com/jjclzhS.png)       |  ![Screenshot 2](https://i.imgur.com/m73eQXI.png)|![Screenshot 3](https://i.imgur.com/ve8LkiB.png)|

## Downloads

<div align="center">

### Desktop Applications

| Platform | Format | Download |
|:--------:|:------:|:--------:|
| Windows | Installer | [**RateMe_1.0.4-4.exe**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4.exe) |
| Windows | Portable | [**RateMe_1.0.4-4_portable.zip**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4_portable.zip) |
| macOS | Universal | [**RateMe_1.0.4-4.dmg**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4.dmg) |

### Linux Packages

| Format | Architecture | Download |
|:------:|:-----------:|:--------:|
| AppImage | x86_64 | [**RateMe_1.0.4-4.AppImage**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4.AppImage) |
| DEB | amd64 | [**RateMe_1.0.4-4_amd64.deb**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4_amd64.deb) |
| RPM | x86_64 | [**RateMe_1.0.4-4_x86_64.rpm**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4_x86_64.rpm) |
| Flatpak | Universal | [**RateMe_1.0.4-4.flatpak**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4.flatpak) |
| Arch Linux | - | [**AUR Instructions**](#arch-linux) |

### Mobile Applications

| Platform | Version | Download |
|:--------:|:-------:|:--------:|
| Android | Universal | [**RateMe_1.0.4-4.apk**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4.apk) |
| Android | arm64-v8a | [**RateMe_1.0.4-4_arm64-v8a.apk**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4_arm64-v8a.apk) |
| Android | armeabi-v7a | [**RateMe_1.0.4-4_armeabi-v7a.apk**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4_armeabi-v7a.apk) |
| Android | x86_64 | [**RateMe_1.0.4-4_x86_64.apk**](../../releases/download/v1.0.4-4/RateMe_1.0.4-4_x86_64.apk) |
| iOS | - | Coming soon |

</div>

## Installation

### Windows
1. Installer: Run `RateMe_1.0.4-4.exe` and follow the installation wizard
   - Or -
2. Portable: Extract `RateMe_1.0.4-4_portable.zip` and run `RateMe.exe`

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
1. Download `RateMe_1.0.4-4.dmg`
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
1. Download `RateMe_1.0.4-4.AppImage`
2. Make it executable:
```bash
chmod +x RateMe_1.0.4-4.AppImage
```
3. Run it:
```bash
./RateMe_1.0.4-4.AppImage
```
No installation needed - the AppImage is portable and works on most Linux distributions.

#### DEB Package (Ubuntu/Debian)
```bash
sudo apt install ./RateMe_1.0.4-4_amd64.deb
```

#### RPM Package (Fedora/RHEL)
```bash
sudo dnf install ./RateMe_1.0.4-4_x86_64.rpm
```

#### Flatpak Installation

1. Download the Flatpak package from [releases](../../releases/download/v1.0.4-4/RateMe_1.0.4-4.flatpak)

2. Install required runtime (if not already installed):
```bash
flatpak install flathub org.freedesktop.Platform//21.08
```

3. Install RateMe:
```bash
flatpak install ./RateMe_1.0.4-4.flatpak
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
- [iTunes API](https://affiliate.itunes.apple.com/resources/documentation/itunes-store-web-service-search-api/): Utilized to search for albums and retrieve detailed album data, the iTunes API serves as the primary data source for the application.
- **JSON Parser for Bandcamp**: A JSON parser is used to search and retrieve detailed album data from Bandcamp links.

## Getting Started

1. Clone the repository: `git clone https://github.com/ALi3naTEd0/RateMe.git rateme`
2. Navigate to the project directory: `cd rateme`
3. Install dependencies: `flutter pub get`
4. Run the application: `flutter run`

## How to Use

1. **Album Search**: Start by entering the artist's name, album title, or URL (iTunes, Apple Music, or Bandcamp) in the search bar to initiate a search for albums.
2. **Rate Songs**: Upon selecting an album, rate each song individually by assigning a rating from 0 to 10.
3. **View Album Details**: Explore comprehensive details about each album, including artist information, release date, and total album duration.
4. **Saved History**: Access your saved ratings history to review past ratings and make any necessary edits.
5. **Export and Import Data**: Use the export and import options to back up your rating data or transfer it to other devices.

## Project Architecture

This Flutter project follows a modular architecture and uses the Provider pattern for state management. The main components are described below:

### Main Components

1. **MusicRatingApp**: Main widget handling theme state and persistence
2. **SearchPage**: Album search interface with iTunes/Bandcamp support
3. **SavedRatingsPage**: Album list management and ratings display
4. **CustomListsPage**: Custom collections management
5. **DetailsPage**: Album details and rating interface
6. **UserData**: Data persistence and management utility

### Data Handling

- **SharedPreferences**: Local storage for albums, ratings, and preferences
- **HTTP**: API requests to iTunes and JSON parsing for Bandcamp
- **HTML**: Extraction of structured data from Bandcamp pages

### External Integrations

- **iTunes API**: Album and track information via official API
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

- Implementation of a recommendation system based on user ratings
- Integration with additional music streaming services
- Functionality to share ratings on RateYourMusic.com
- Offline mode to access ratings without an internet connection

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
- [html](https://pub.dev/packages/html) - HTML parsing for structured data
- [url_launcher](https://pub.dev/packages/url_launcher) - External URL handling
- [intl](https://pub.dev/packages/intl) - Date formatting
- [path_provider](https://pub.dev/packages/path_provider) - File system access
- [file_picker](https://pub.dev/packages/file_picker) - File selection dialogs
- [share_plus](https://pub.dev/packages/share_plus) - Content sharing
- [package_info_plus](https://pub.dev/packages/package_info_plus) - App version info

## Contact

[Discord](https://discord.gg/UQ55AVv4ZY)

Project Link: [https://github.com/ALi3naTEd0/RateMe](https://github.com/ALi3naTEd0/RateMe)

## Documentation
- [Changelog](CHANGELOG.md)

---
Developed with ♥ by [X](https://github.com/ALi3naTEd0)
