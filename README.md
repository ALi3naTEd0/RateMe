<img src="assets/rateme.png" width="200">

# Rate Me!

![Version](https://img.shields.io/badge/version-1.0.0--1-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-green)
![Downloads](https://img.shields.io/github/downloads/ALi3naTEd0/RateMe/total)
![Last Commit](https://img.shields.io/github/last-commit/ALi3naTEd0/RateMe)
![Stars](https://img.shields.io/github/stars/ALi3naTEd0/RateMe)

[Discord](https://discordapp.com/channels/@me/343448030986371072/)

## Table of Contents
- [Introduction](#introduction)
- [Screenshots](#screenshots)
- [Downloads](#downloads)
- [Installation](#installation)
- [Features](#features)
- [Technologies Used](#technologies-used)
- [Getting Started](#getting-started)
- [How to Use](#how-to-use)
- [Project Architecture](#project-architecture)
- [Development](#development)
- [Roadmap](#roadmap)
- [Contributions](#contributions)
- [License](#license)
- [Acknowledgements](#acknowledgements)
- [Contact](#contact)

## Introduction

Welcome to **Rate Me!**, an app designed for music lovers to discover, rate, and manage your favorite albums effortlessly. With **Rate Me!**, you can explore a wide variety of albums, rate each song individually, and get an overall view of the album's quality based on your personal ratings.

## Screenshots

| | | |
|:-------------------------:|:-------------------------:|:-------------------------:|
|![Screenshot 1](https://i.imgur.com/jjclzhS.png)       |  ![Screenshot 2](https://i.imgur.com/m73eQXI.png)|![Screenshot 3](https://i.imgur.com/ve8LkiB.png)|

## Downloads
| Windows      | MacOS        | Linux        | Android      | iOS          |
|--------------|--------------|--------------|--------------|--------------|
| [Installer](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-Setup.zip)    | [DMG](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-DMG.zip)  |  [DEB](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/rateme-DEB.zip) | [APK-Universal](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/rateme-universal.zip)       | Maybe?       |
| [Portable](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-Portable.zip)     |              |  [RPM](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/rateme-RPM.zip)            | [APK-arm64-v8a](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/rateme-arm64-v8a.zip)             |              |
|              |              |   [ARCH](#arch-install)           | [APK-armeabi-v7a](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/rateme-armeabi-v7a.zip)      |              |
|              |              |   [AppImage](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/rateme-AppImage.zip)           | [APK-x86_x64](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/rateme-x86_64.zip)               |              |

## Installation

### Windows
1. Installer: Run `RateMe-v1.0.0.exe` and follow the installation wizard
   - Or -
2. Portable: Extract `RateMe-portable.zip` and run `RateMe.exe`

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
1. Download `RateMe.dmg`
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
1. Download `RateMe_1.0.0-1.AppImage`
2. Make it executable:
```bash
chmod +x RateMe_1.0.0-1.AppImage
```
3. Run it:
```bash
./RateMe_1.0.0-1.AppImage
```
No installation needed - the AppImage is portable and works on most Linux distributions.

#### DEB Package (Ubuntu/Debian)
```bash
sudo apt install ./RateMe_1.0.0-1_amd64.deb
```

#### RPM Package (Fedora/RHEL)
```bash
sudo dnf install ./RateMe_1.0.0-1_x86_64.rpm
```

#### Arch Linux
```bash
git clone https://github.com/ALi3naTEd0/RateMe.git
cd RateMe
makepkg -si
```

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

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the `LICENSE` file for more details.

The GPL-3.0 is a strong copyleft license that requires any derivative software to also be open source under the same license. This ensures that the software remains free and open, protecting the rights of users and developers.

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

[Discord](https://discordapp.com/channels/@me/343448030986371072/)

Project Link: [https://github.com/ALi3naTEd0/RateMe](https://github.com/ALi3naTEd0/RateMe)

---
Developed with ♥ by [X](https://github.com/ALi3naTEd0)
