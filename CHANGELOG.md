# RateMe Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive track duration detection for Discogs albums across all available versions
- Smart version selection for Discogs albums based on format, country, and data quality
- Discogs integration with complete search and album details support
- Universal EP/Single handling across all platforms (iTunes/Apple Music, Spotify, Deezer, Discogs)
- Standardized album suffix normalization system for cross-platform compatibility
- Smart detection and cleanup of album name variations (EP, Single, etc.)
- Share functionality for album links on mobile platforms
- Clipboard integration for desktop platforms when sharing
- Enhanced album matching between platforms with improved similarity algorithms
- Special platform-specific matching for album variations
- Context menu for streaming buttons with copy, open, and share options
- Cross-platform streaming integration with buttons for Spotify, Apple Music and Deezer
- Integration with existing Bandcamp links to provide unified streaming experience
- Context menu for streaming buttons with copy URL and open options
- Default search platform selection in settings
- Default search platform persistence across app restarts
- Multi-platform search capability (iTunes, Spotify, Deezer)
- Integrated SQLite database for improved data persistence and performance
- Cross-platform album matching between different music services
- Platform icons in search results for better visual identification
- Platform-specific search capabilities for more accurate results
- Enhanced clipboard detection for URLs from all supported platforms
- Database migration utility with progress tracking
- Database integrity checking and vacuum optimization
- Global notifications system for real-time app state updates
- SVG-based platform icons with proper theme support

### Fixed
- Fixed EP/Single designation mismatches between all music platforms
- Fixed album naming inconsistencies between streaming services
- Improved album title normalization for iTunes, Spotify, Deezer and Discogs
- Enhanced string similarity calculations for better album matches
- Fixed special case handling for album suffix variations across all platforms
- Improved platform detection from album URLs
- Better matching algorithm for finding the same album across different streaming services
- Fixed issues with Deezer track handling, ratings persistence and album artwork display
- Fixed platform icons in light theme showing incorrectly
- Fixed automatic search when changing platforms in the main search bar
- Fixed database timestamp constraints for ratings across all platforms
- Fixed inconsistent handling of track IDs across different music platforms
- Fixed album ratings consistency across different platforms
- Improved error handling for missing track information
- Fixed crashes when loading albums with inconsistent track data
- Better handling of non-standard API responses from music platforms
- Improved track duration detection for Discogs albums with multiple release versions
- Enhanced version selection logic to handle albums with variant track listings

### Changed
- Improved Discogs album data quality with intelligent version selection algorithm
- Enhanced logging for easier debugging of platform-specific integration issues
- Universal album name normalization system for all platforms
- Enhanced algorithm for EP/Single name cleanup across all music services
- Added direct album name comparison after standardization for all platforms
- Improved multi-platform album matching with standardized naming conventions
- Reorganized Settings page with grouped options for search preferences
- Enhanced default platform selection with visual platform indicators
- Implemented automatic platform updates when default is changed in settings
- Enhanced data model with more consistent field naming
- Improved album detail page loading performance
- Enhanced platform detection from URLs
- Reorganized search service to better handle multiple platforms
- Improved search result ranking algorithm

### Technical
- Centralized album name normalization with regex-based suffix detection
- Standardized string comparison utilities for better text matching
- Platform-agnostic album title cleanup system
- Improved platform service factory with better error handling
- Improved BuildContext management with GlobalKey approach
- Added StreamController-based global notification system
- Enhanced error logging for platform-specific issues
- Added database helper methods for SQLite operations
- Added migration utility for data transition to SQLite
- Implemented transaction support for batch database operations
- Better album matching algorithms for cross-platform compatibility
- Optimized search queries with improved platform handling

## [1.1.0-4] - 2023-10-31

### Added
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
- Fixed track ID handling with multiple fallback mechanisms for consistent string IDs
- Fixed album deletion cascading to custom lists
- Fixed custom list content synchronization on album deletion
- Fixed ratings not being calculated correctly in some cases
- Fixed album artwork display inconsistencies across the app
- Fixed database schema migration and backward compatibility issues
- Fixed data integrity issues when accessing album artwork
- Fixed non-null constraint error on ratings timestamp
- Fixed album ratings persistence and display for all supported platforms
- Improved track loading reliability across different music platforms
- Fixed issues with Spotify album tracks not displaying properly

### Changed
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

## [1.1.0-3] - 2023-10-25

### Added
- Comprehensive SQLite database implementation for all app data
- Migration utility to transition from SharedPreferences to SQLite
- Migration progress UI with detailed statistics
- Database helper class with extensive error handling
- Support for backup/restore in new database format
- Track ID consistency layer for cross-platform compatibility

### Fixed
- Fixed inconsistent behavior when retrieving album artwork
- Improved error handling for missing track information
- Fixed crashes when loading albums with inconsistent track data
- Better handling of non-standard API responses from music platforms

### Changed
- Enhanced data model with more consistent field naming
- Improved album detail page loading performance
- Better album rating consistency across platforms

## [1.1.0-2] - 2023-10-20

### Added
- Enhanced search capabilities for Spotify albums
- Added dedicated Spotify authentication flow
- Improved album match detection between platforms

### Fixed
- Fixed platform icon display issues in settings
- Better error handling for API failures
- Corrected track filtering to exclude videos and other non-music content

### Changed
- Improved clipboard detection for URLs from different music platforms
- Enhanced search result ranking algorithm

## [1.1.0-1] - 2023-10-19

### Added
- Initial support for Deezer platform integration
- Cross-platform album matching capability
- Platform icons in search results
- Expanded platform selection in search interface

### Fixed
- Fixed shared preferences persistence issues
- Better error handling for network failures
- Improved album artwork resolution selection

### Changed
- Reorganized search service to better handle multiple platforms
- Enhanced platform detection from URLs

## [1.0.4-4] - 2023-10-15

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

## [1.1.0] - 2023-06-18
- Added album rating persistence
- Added track ratings
- Added track listing display
- Fixed UI issues on smaller screens

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
