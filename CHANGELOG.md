# Changelog

All notable changes to the RateMe app will be documented in this file.

## [Unreleased]

### Added
- Unified Data Model to ensure consistent handling of albums across different platforms
- Conversion utilities to safely migrate legacy data to the new model
- Debug tools for diagnosing data issues
- New Settings options for data management
- Improved error handling throughout the app
- Support for different music platforms with standardized data format
- Better backward compatibility with older app versions
- Support for Spotify URLs in clipboard detection
- Platform icons for better visual identification of music sources (Apple Music, Spotify, Bandcamp)
- Better error handling for album data parsing
- Global clipboard monitoring for easier URL import

### Changed
- Reorganized Settings page with grouped options
- Improved album import/export functionality
- Enhanced custom lists management
- More robust sharing functionality
- Better handling of app themes and colors
- UI/UX Improvement: Applied consistent 85% width layout to all screens for better readability
- Refactored entire app from BuildContext-based navigation to GlobalKey approach
- Added tooltips for track names that display full title on hover
- Improved responsive design for various screen sizes
- Enhanced image sharing capabilities
- Standardized page layouts across all screens

### Fixed
- Issues with albums not appearing in custom lists
- Problems with inconsistent album data structure
- Rating calculation errors on some albums
- Display issues with album artwork on certain devices
- Custom list sorting and reordering bugs
- Various stability improvements
- Issue with slider tooltips not displaying properly
- Inconsistent UI widths between different screens
- Rating verification process for improved data integrity
- Platform detection for different album sources
- Album migration and conversion reliability

### Technical
- Reduced context-dependent code for better maintainability
- Implemented consistent navigation pattern using GlobalKeys
- Improved error logging throughout the application
- Optimized performance with const constructors where appropriate
- Better separation of UI and business logic

## [2.0.0] - 2025-03-20

### Added
- Improved color picker with live preview in settings
- Better theme persistence across app restarts
- Option to choose between light/dark button text
- Improved album search with better handling of clean/explicit versions
- URL detection from clipboard for quick album import

### Changed
- Unified button text style for better consistency
- Slider colors now properly follow theme's primary color
- Color picker preview now shows actual button style
- Enhanced search results organization and deduplication
- Improved Bandcamp album handling

### Fixed
- Theme color not persisting after app restart
- Inconsistent button text colors across the app
- Sliders not updating color when changing theme
- Duplicate album entries in search results
- Missing track information from some sources

## [1.5.0] - 2025-01-15

### Added
- Support for Bandcamp albums
- Custom lists feature to organize albums
- Share albums as beautiful images
- Dark mode support
- Custom color themes

### Changed
- Improved UI for rating albums
- Better handling of album metadata
- Enhanced search functionality

### Fixed
- Various bugs and stability issues

## [1.0.0] - 2024-12-01

### Added
- Initial release
- Apple Music album search
- Track-by-track rating system
- Album average calculation
- Basic data export/import

## [1.0.4-4] - 2025-07-22

### Changed
- Changed project license from GPL-3.0 to MIT
- Centralized version management in dedicated footer.dart file
- Updated Discord server link to official server
- Standardized application name to "Rate Me!" across all platforms
- Improved desktop integration for Linux packages
- Fixed icon issues in Arch Linux package
- Consistent icon naming across all Linux packages

### Added 
- Flatpak package support for Linux
- Full GTK theme support in all Linux packages
- Support for multiple languages with initial internationalization
- Spanish translations
- Improvements to the theme system

### Fixed
- Fixed Android app not launching on some devices
- Fixed track filtering to exclude videos from iTunes results
- Fixed portable Windows package structure with data directory
- Fixed release workflow for proper version propagation
- Icon visibility in Arch Linux package
- GTK dependencies in Flatpak package
- Desktop entry consistency across all Linux distributions
- Missing exclamation mark in application name
- Issues with file picker on Linux
- Proper display of albums with special characters
- Better error handling in album searches

## [1.0.4-3] - 2025-07-15

### Added
- Flatpak support for Linux
- Enhanced album sharing functionality

### Fixed
- Fixed Android app not launching on some devices
- Fixed track filtering to exclude videos from iTunes results
- Fixed portable Windows package structure with data directory
- Improved version management and documentation
- Fixed release workflow for proper version propagation
- Issues with Windows installer
- UI loading time

## [1.0.4-2] - 2025-07-10

### Fixed
- Fixed portable Windows package structure
- Updated documentation and downloads layout
- Simplified Linux artifacts (single tarball)

## [1.0.4-1] - 2025-02-29

### Fixed
- Fixed track count inconsistency by properly filtering video tracks
- Corrected track saving in custom lists and saved albums
- Ensured consistent track filtering across all album views
- Fixed track data persistence when saving albums

## [1.0.3-1] - 2025-02-28

### Added
- Implement centralized theme system for better consistency across the app
- Improve slider contrast in dark mode with purple background and white text

### Fixed
- Fix custom lists reordering persistence
- Update URL launching implementation on Linux platforms to fix opening links
- Improve cross-platform compatibility for file operations

### Changed
- Translate remaining Spanish comments to English
- Clean up Android builds naming format
- Update documentation and build workflows
- Improve performance of lists rendering
- Enhance dark mode appearance
- Standardized options button icon from more_vert to settings across all screens
- Improved options dialog consistency by removing redundant settings option
- Enhanced visual consistency in options menus throughout the app

## [1.0.2-1] - 2024-05-01

### Added
- New footer with version information
- Clickable version to display about dialog

### Fixed
- Improved error handling for URL launching
- Fixed rating consistency between sessions

### Changed
- Updated dependencies to latest versions
- Improved UI responsiveness

## [1.0.1-1] - 2024-04-27

### Added
- Custom lists feature for organizing albums
- Export and import albums functionality
- Share ratings as image

### Fixed
- Bandcamp parsing edge cases
- Album duplication issues

### Changed
- Improved search functionality
- Enhanced UI for smaller screens

## [1.0.0-1] - 2024-04-15

Initial release

### Features
- Search and browse albums from iTunes and Bandcamp
- Rate albums and individual tracks
- Save ratings locally
- Dark mode support
- Import/export backup functionality
