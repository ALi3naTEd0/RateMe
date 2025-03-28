# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Full Deezer integration with API support for album search and track retrieval
- Deezer album URL detection in clipboard
- Multi-platform consistency for album ratings (iTunes, Bandcamp, Spotify, Deezer)
- Implemented SQLite database with migration from SharedPreferences
- Created unified data models for albums, tracks, ratings, lists
- Added database maintenance tools (vacuum, integrity check)
- Added schema detection and column mapping for backward compatibility
- Added transaction support for batch operations
- Improved error handling and debug logging for database operations
- Added database backup/restore functionality with enhanced format
- Support for Spotify URLs in clipboard detection
- Platform icons for better visual identification of music sources
- Standardized UI component sizes for rating boxes and list icons to 48x48px
- New skeleton loading screens for improved UX during content loading

### Fixed
- Fixed Deezer track handling, ratings persistence and album artwork display
- Fixed database timestamp constraints for ratings across all platforms
- Fixed track ID handling with multiple fallback mechanisms for consistent string IDs
- Fixed album deletion cascading to custom lists
- Fixed custom list content synchronization on album deletion
- Fixed ratings not being calculated correctly in some cases
- Fixed album artwork display inconsistencies across the app
- Fixed database schema migration and backward compatibility issues
- Fixed data integrity issues when accessing album artwork
- Fixed non-null constraint error on ratings timestamp
- Fixed album ratings persistence and display for all supported platforms (iTunes, Bandcamp, Spotify, Deezer)
- Improved track loading reliability across different music platforms
- Fixed issues with Spotify album tracks not displaying properly
- Fixed issues with Deezer track ratings not being saved correctly
- Fixed inconsistent handling of track IDs across different music platforms

### Changed
- Reorganized Settings page with grouped options for database management
- Enhanced custom lists management with SQLite backend
- UI/UX Improvement: Applied consistent 85% width layout to all screens
- Refactored entire app from BuildContext-based navigation to GlobalKey approach
- Added tooltips for track names that display full title on hover
- Improved responsive design for various screen sizes
- Improved dialog layout and sizing consistency across the app
- Added checkbox-based list selection for better list management UX
- Enhanced database schema validation
- Improved rating error handling with multiple fallback mechanisms

### Technical
- Reduced context-dependent code for better maintainability
- Implemented consistent navigation pattern using GlobalKeys
- Improved error logging throughout the application
- Optimized performance with const constructors where appropriate
- Better separation of UI and business logic
- Implemented proper transaction support for database operations
- Added database integrity checks and repair functionality
- Created migration utilities for safe data transition
- Optimized database queries with prepared statements

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

## [1.0.4-4] - 2025-07-22

### Changed
- Changed project license from GPL-3.0 to MIT
- Centralized version management in dedicated footer.dart file
- Updated Discord server link to official server
- Standardized application name to "Rate Me!" across all platforms
- Improved desktop integration for Linux packages
- Fixed icon issues in Arch Linux package
- Consistent icon naming across all Linux packages
- Improved album search results relevance
- Reduced album load time by optimizing database queries
- Updated footer with version links

### Added 
- Flatpak package support for Linux
- Full GTK theme support in all Linux packages
- Support for multiple languages with initial internationalization
- Spanish translations
- Improvements to the theme system
- Bandcamp album support
- User-adjustable primary color option in settings
- Full album export and import

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
- Fixed album order persistence when manually reordering
- Fixed inconsistent dark mode text colors on buttons
- Fixed clipboard detection for URLs with query parameters

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

## [1.0.3] - 2025-03-15

### Added
- SQLite database migration for better performance
- Album import from JSON files
- Custom list management

### Fixed
- Fixed duplicate albums in search results
- Fixed rating slider inconsistencies

### Changed
- Improved album detail page layout
- Enhanced error handling and logging

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

## [1.0.2] - 2025-03-08

### Added
- Dark mode support
- Album rating sharing via image export
- Pull-to-refresh in album lists

### Fixed
- Fixed memory leak in album list view

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

## [1.0.1] - 2025-03-01

### Added
- Initial release with basic functionality
- iTunes and Spotify album support
- Track-by-track rating system
- Saved albums management

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

## [1.0.0] - 2024-12-01

### Added
- Initial release
- Apple Music album search
- Track-by-track rating system
- Album average calculation
- Basic data export/import

## [1.0.0-1] - 2024-04-15

Initial release

### Features
- Search and browse albums from iTunes and Bandcamp
- Rate albums and individual tracks
- Save ratings locally
- Dark mode support
- Import/export backup functionality
