<img src="https://github.com/ALi3naTEd0/RateMe/blob/rateme/assets/rateme.png" width="200">

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
| [Installer](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-v1.0.0.exe)    | [DMG](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe.dmg)  | [ARCH](#arch-install)  | [APK-Universal](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe.apk)       | Maybe?       |
| [Portable](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-portable.zip)     |  [APP](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-macOS-Universal.zip)            |  [DEB](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe_1.0.0-1_amd64.deb)            | [APK-arm64-v8a](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-arm64-v8a-release.apk)             |              |
|              |              |   [RPM]()           | [APK-armeabi-v7a](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-armeabi-v7a-release.apk)      |              |
|              |              |   [AppImage](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe.AppImage)           | [APK-x86_x64](https://github.com/ALi3naTEd0/RateMe/releases/download/v1.0.0%2B1/RateMe-x86_64-release.apk)               |              |

### Arch Install
```
git clone https://github.com/ALi3naTEd0/RateMe.git
cd RateMe
makepkg -si
```

### AppImage Install
1. Download RateMe.AppImage from the latest release
2. Make it executable:
```bash
chmod +x RateMe.AppImage
```
3. Run it:
```bash
./RateMe.AppImage
```

No installation needed - the AppImage is portable and will work on most Linux distributions.

<!---
### Installation on macOS

1. Download the RateMe-Universal.zip file from the latest release
2. Double-click the zip file to extract it
3. Drag and drop "rateme.app" to your Applications folder
4. The first time you run the app:
   - Right-click (or Control-click) on the app
   - Select "Open" from the menu
   - Click "Open" in the security dialog

Note: This is a universal build that works on both Intel and Apple Silicon Macs running macOS 10.14 or later.

Troubleshooting: If you get a "App is damaged" or "not supported" message:
```bash
# Open Terminal and run:
xattr -cr "/Applications/rateme.app"
codesign --force --deep --sign - "/Applications/rateme.app"
```
--->

## Features

- **Album Search**: Easily find albums by entering the artist's name, album title, or iTunes, Apple Music, or Bandcamp URL.
- **Song Rating**: Rate each song within an album on a scale of 0 to 10, expressing your opinions on each track in detail.
- **Average Rating Calculation**: The app dynamically calculates an average rating for each album based on the individual song ratings.
- **Album Details**: Access detailed information about each album, including the artist's name, album title, release date, and total album duration.
- **Saved History**: Access your saved ratings history to review past ratings and make any necessary edits.
- **Edit Old Saved Ratings**: Modify or update previously saved ratings for albums and songs, giving you the flexibility to refine your ratings over time.
- **Export and Import Data**: Export and import your rating data to back it up or transfer it between devices.
- **No Login Required**: Start using the app immediately without the need to log in or authenticate.
- **Bandcamp Integration**: Support for Bandcamp links allows you to search and rate albums directly from Bandcamp.

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

1. **MusicRatingApp**: The main widget of the application. It handles the global theme state (light/dark) and persists it using SharedPreferences.
2. **SearchPage**: Allows users to search for albums on iTunes or enter Bandcamp URLs. It uses debouncing to optimize API calls.
3. **SavedRatingsPage**: Displays saved albums and their ratings. Allows reordering the list and deleting albums.
4. **AlbumDetailsPage**: Shows details of an iTunes album, including tracks and their individual ratings. Allows users to rate tracks and save the album.
5. **BandcampSavedAlbumPage**: Displays details of a Bandcamp album, including tracks and their ratings. Supports rating tracks and saving the album.
6. **UserData**: Utility class for handling data persistence using SharedPreferences. Manages saving and retrieving album data and ratings.

### Data Handling

- **SharedPreferences**: Used to locally store saved albums, ratings, and user preferences.
- **HTTP**: Used to make requests to the iTunes API and retrieve album information.
- **HTML Parser**: Utilized to parse Bandcamp album pages and extract relevant information.

### Services

- **BandcampService**: Handles the logic for obtaining album information from Bandcamp.
- **BandcampParser**: Extracts track information and release date from Bandcamp HTML pages.

### Themes

- **AppTheme**: Defines the light and dark themes of the application.

### Reusable UI Components

- **Footer**: Reusable footer widget used across various screens.

### Key Features

1. Album search on iTunes and Bandcamp
2. Saving albums and ratings
3. Viewing saved albums and their details
4. Rating individual tracks for both iTunes and Bandcamp albums
5. Calculating average rating per album
6. Switching between light/dark themes
7. Exporting and importing preferences
8. Integration with RateYourMusic for additional album information

### External Integrations

- **iTunes API**: Used to fetch album and track information for iTunes albums.
- **Bandcamp**: Web scraping is used to fetch album and track information from Bandcamp pages.
- **RateYourMusic**: Provides a link to search for the album on RateYourMusic for additional ratings and reviews.

This architecture allows for a clear separation of concerns, facilitating project maintenance and scalability. It also provides a consistent user experience across different music platforms (iTunes and Bandcamp) while maintaining platform-specific data retrieval methods.

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

- [http](https://pub.dev/packages/http) - Used for making HTTP requests to the iTunes API
- [shared_preferences](https://pub.dev/packages/shared_preferences) - Used for storing simple data locally
- [provider](https://pub.dev/packages/provider) - Used for state management in the application
- [html](https://pub.dev/packages/html) - Used for parsing HTML content from Bandcamp pages
- [path_provider](https://pub.dev/packages/path_provider) - Used for finding commonly used locations on the filesystem
- [flutter_xlider](https://pub.dev/packages/flutter_xlider) - Used for creating customizable range sliders
- [url_launcher](https://pub.dev/packages/url_launcher) - Used for launching URLs in the mobile platform
- [file_selector](https://pub.dev/packages/file_selector) - Used for selecting files or directories
- [file_picker](https://pub.dev/packages/file_picker) - Used for picking files from the device storage
- [file_saver](https://pub.dev/packages/file_saver) - Used for saving files to the device
- [permission_handler](https://pub.dev/packages/permission_handler) - Used for handling runtime permissions
- [share_plus](https://pub.dev/packages/share_plus) - Used for sharing content from the app
- [csv](https://pub.dev/packages/csv) - Used for parsing and encoding CSV data
- [intl](https://pub.dev/packages/intl) - Used for internationalization and localization

## Contact

[Discord](https://discordapp.com/channels/@me/343448030986371072/)

Project Link: [https://github.com/ALi3naTEd0/RateMe](https://github.com/ALi3naTEd0/RateMe)

---
Developed with ♥ by [X](https://github.com/ALi3naTEd0)
