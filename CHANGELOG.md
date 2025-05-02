# RateMe Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### New Logo Implementation Across All Platforms
- Designed and implemented a new modern logo for better brand identity
- Created optimized logo assets for all supported platforms (Android, iOS, Windows, macOS, Linux)
- Implemented adaptive icon support for Android with proper foreground/background layers
- Added high-resolution icons for desktop platforms with proper scaling
- Updated app icon in package manifests for all platforms
- Ensured proper icon display in OS task managers and app launchers
- Optimized SVG source files for better scaling and rendering
- Created platform-specific variants to match OS design guidelines

### Major Database Migration & Persistence Overhaul
- Complete rewrite of app's core data persistence from SharedPreferences to SQLite
- New database architecture providing better performance, reliability and data integrity
- Backward compatibility with previous versions through guided migration process
- Extensive logging and error handling for diagnosing database issues
- Implementation of transaction support for data consistency
- Database maintenance tools including vacuum, integrity checks, and emergency reset
- Cross-platform data migration with progress tracking
- Recovery mechanisms for database connection issues

### Theme System Redesign
- Complete overhaul of app theming with new ThemeService architecture
- Centralized theme management with reactive updates across the app
- Support for dynamic theme and color changes without app restart
- Fixed critical color corruption issues with proper color value handling
- Fixed hex color representation issues ensuring consistent RGB to hex conversion
- Fixed color picker issues with direct integer-based RGB handling
- Support for dark mode, light mode and system default with seamless transitions
- Consistent 85% width design pattern across all UI components
- Fixed black color issue on Android devices with proper "safe black" implementation
- Eliminated flashing of default purple color during app startup with theme preloading
- Proper color persistence across app restarts

### Added
- Secure user-provided API key support for Spotify and Discogs services
- Dedicated API key management section in the Settings page
- Automatic API key validation for Spotify credentials
- Detailed API setup instructions with step-by-step guidance
- Clear status indicators showing connected API services
- Helpful context for why certain services require API keys
- Direct links to developer portals for obtaining API credentials
- Complete migration from SharedPreferences to SQLite database for all settings and user data
- Reliable track data persistence for all platforms (iTunes/Apple Music, Spotify, Deezer, Discogs, Bandcamp)
- Fixed Bandcamp album metadata storage with proper track information preservation
- Multi-level metadata extraction from various album data sources for maximum reliability
- Custom hex color input field in color picker for precise color selection
- Interactive color preview in settings for immediate feedback
- Improved support option in About dialog
- Enhanced footer with version information and sponsor links
- Consistent notification styling with 85% width to match app theme
- Refined database maintenance tools with appropriate icons
- Emergency reset option for critical database issues
- Complete migration from SharedPreferences to SQLite database for all app settings
- New database helper methods for settings management
- Centralized version tracking with version_info.dart
- Automatic migration of remaining SharedPreferences data
- Final cleanup utility for SharedPreferences
- Database integrity verification and repair tools
- Enhanced album ID handling for cross-platform compatibility
- Improved error recovery for database operations
- Support for backup and restore of all settings
- More reliable track ID handling with position-based fallbacks
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
- Fixed Spotify and Discogs search results showing only when API keys are provided
- Enhanced API key persistence using secure database storage
- Fixed platform-specific search behavior when API keys are missing
- Improved error handling for failed API authentication attempts
- Fixed user-facing API documentation links
- Improved log management with reduced verbosity and better organization
- Fixed redundant artwork URL logging during album display
- Optimized logging for better debug experience and reduced noise
- Eliminated duplicate artwork URL lookups and logs
- Fixed performance issues related to excessive logging
- Streamlined logging for album loading to prevent redundant messages
- Critical issue with color picker not displaying correct hex values for selected colors
- Fixed RGB to hex conversion ensuring exact values are preserved across the application
- Fixed variable usage in color handling to prevent duplicate definitions
- Critical issue with Bandcamp albums not storing track information properly
- Improved metadata extraction for albums with multiple track data sources
- Fixed track persistence for albums from all supported platforms
- Multiple metadata extraction strategies for maximum data reliability
- Critical color handling issues with reliable RGB value storage and retrieval
- Theme consistency issues with proper state management and persistence
- Settings page color picker corruption with proper color value normalization
- Race condition in ThemeService preventing proper theme application
- Implemented robust error handling for database operations
- Fixed notification issues with standardized 85% width for consistent UI
- Fixed album conversion using appropriate JsonFixer implementation
- Fixed duplicate functionality for Bandcamp album updating and album format conversion
- Eliminated corrupted colors (particularly black and near-black colors) through proper value handling
- Fixed color selection in settings page to always use correct color channels
- Platform-specific path issues for data storage
- Proper disposal of resources to prevent memory leaks
- Improved state handling for asynchronous operations

### Changed
- Redesigned API key management interface with platform-specific sections
- Improved API configuration UX with connection status indicators and help resources
- Redesigned Settings screen with dedicated API management section
- Enhanced search results to indicate when results are limited due to missing API keys
- Enhanced log output with clearer summaries of loaded data
- Improved logging organization with proper counter-based summaries
- Reduced verbose logging for frequent operations to improve performance
- Consolidated artwork URL lookups to avoid redundant processing
- Reorganized Settings page with more intuitive grouping of options
- Updated icons for better visual representation of functionality
- Improved About dialog with additional support options and GitHub sponsor links
- Replaced SharedPreferences with SQLite for all settings storage
- Improved startup performance with optimized database initialization
- Enhanced error handling throughout settings management
- Added proper database transaction support for settings operations
- Simplified theme management with direct database access
- More consistent API for accessing user preferences
- Better organization of settings with standardized access methods
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
- Enhanced rating persistence with a robust position-based fallback system
- Refactored track rating display with consistent handling across platforms
- Improved track name storage and retrieval from database

### Technical
- Implemented secure API key storage in SQLite database
- Created centralized ApiKeys and ApiKeyManager classes for better credential management
- Added API key validation system with proper error handling
- Added conditional search behavior based on available credentials
- Implemented platform-specific configuration UI components
- Enhanced service factory to handle authentication failures gracefully
- Added artwork URL caching during album processing for better performance
- Implemented efficient artwork URL extraction across multiple data source formats
- Added data summary logging for better troubleshooting
- Improved logging consistency with single-responsibility pattern
- Enhanced saved albums display with optimized artwork detection and handling
- Reduced debug log noise by eliminating redundant messages
- Added log summaries for batch operations to improve monitoring
- Implemented pre-processed data storage to avoid redundant lookups
- Implemented centralized version tracking system
- Added consistent notification formatting for better UX
- Improved SnackBar appearance with standardized width
- Enhanced sponsor integration for better project support options
- Created DatabaseHelper with comprehensive settings support
- Added automatic database initialization during app startup
- Implemented robust error handling for all database operations
- Added migration utility for SharedPreferences to SQLite
- Enhanced logging for database operations
- Added database schema validation and repair tools
- Improved backup and restore capabilities
- More consistent API for settings management
- Connected track ratings with SQLite database storage for persistent ratings
- Added position-based track ID matching for ratings when direct ID match fails
- Fixed recursive method calls causing stack overflow errors in rating display
- Implemented robust track metadata saving with ratings in database
- Added reliable fallback mechanisms when track data is incomplete
- Added extensive debug logging for rating matching and persistence
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

## [1.1.0-4] - 2025-04-02

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

## [1.1.0-3] - 2025-03-30

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

## [1.0.4-4] - 2025-03-07

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
- Updated documentation links for consistent file naming
- Improved Linux artifacts naming consistency
- Improved version management and documentation

### Added 
- Flatpak package support for Linux
- Full GTK theme support in all Linux packages
- Support for multiple languages with initial internationalization
- Spanish translations
- Improvements to the theme system
- Bandcamp album support
- User-adjustable primary color option in settings
- Full album export and import
- Enhanced album sharing functionality

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
- Issues with Windows installer
- UI loading time
- Fixed track count inconsistency by properly filtering video tracks
- Corrected track saving in custom lists and saved albums
- Ensured consistent track filtering across all album views
- Fixed track data persistence when saving albums
- Updated documentation and downloads layout
- Simplified Linux artifacts (single tarball)

## [1.0.3-1] - 2025-02-28

### Added
- SQLite database migration for better performance
- Album import from JSON files
- Custom list management
- Centralized theme system for better consistency across the app
- Improved slider contrast in dark mode with purple background and white text

### Fixed
- Fixed duplicate albums in search results
- Fixed rating slider inconsistencies
- Fixed custom lists reordering persistence
- Updated URL launching implementation on Linux platforms to fix opening links
- Improved cross-platform compatibility for file operations

### Changed
- Improved album detail page layout
- Enhanced error handling and logging
- Translated remaining Spanish comments to English
- Cleaned up Android builds naming format
- Updated documentation and build workflows
- Improved performance of lists rendering
- Enhanced dark mode appearance
- Standardized options button icon from more_vert to settings across all screens
- Improved options dialog consistency by removing redundant settings option
- Enhanced visual consistency in options menus throughout the app

## [1.0.2-1] - 2025-02-26

### Added
- Dark mode support
- Album rating sharing via image export
- Pull-to-refresh in album lists
- Clickable version footer for better discoverability
- Improved version display in About dialog

### Fixed
- Fixed memory leak in album list view

### Changed
- Updated versionCode to 3 and versionName to 1.0.2
- Ensured smooth app updates on Android devices

## [1.0.0-1] - 2025-02-18

### Initial Stable Release

A comprehensive music rating app with multi-platform support and features:

#### Core Features
- Album search via iTunes API and Bandcamp integration
- Track-by-track rating system (0-10)
- Custom album collections and list management
- Light/Dark theme support
- Backup and restore functionality
- RateYourMusic integration

#### Platform Support
- Windows: Installer and portable versions
- macOS: DMG with Gatekeeper bypass support
- Linux: AppImage, DEB, RPM packages
- Android: Universal and architecture-specific APKs

#### UI/UX Improvements
- Optimized DataTable layout for track listings
- Responsive design for all screen sizes
- Improved rating slider interaction
- Consistent layout across platforms

#### Data Management
- JSON-based import/export system
- Individual album data sharing
- Collection backup functionality
- Custom lists with drag-and-drop support

#### Image Sharing
- High-quality album rating screenshots
- Collection sharing capabilities
- Proper MediaScanner integration on Android
- Save to Downloads or share directly

#### Technical Enhancements
- Efficient JSON-LD parsing for Bandcamp
- Improved data persistence layer
- Better error handling and logging
- Platform-specific optimizations

## [0.0.9-6] - 2024-09-01

### Added
- Android support
- Mobile-friendly UI adjustments
- Responsive design for different screen sizes
- Touch-optimized controls for rating
- Android-specific file storage implementation
- Permission handling for Android

### Fixed
- UI scaling issues on smaller screens
- Navigation issues on mobile devices
- Album artwork loading on Android

## [0.0.9-5] - 2024-06-16

### Added
- Bandcamp album support
- Web scraper for Bandcamp album data
- Track parsing from Bandcamp pages
- Improved album artwork resolution from Bandcamp

### Fixed
- Improved error handling for network requests
- Better handling of album data variations

## [0.0.9-4] - 2024-06-09

### Added
- Windows only for now
- Initial application structure
- Basic iTunes API integration
- Simple album search capability
- Minimal rating system
- Local storage of ratings
