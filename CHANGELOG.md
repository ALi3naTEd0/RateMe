# RateMe Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Dynamic Theme & Color Features
- **Album Artwork Color Picker**: Extract and select dominant colors from album artwork to personalize the app theme
- Interactive color selection with visual preview of extracted palette colors
- Persistent color storage per album with automatic restoration when viewing saved albums
- Seamless theme integration that updates sliders, buttons, and UI elements with selected colors
- Collapsible color picker interface for clean, unobtrusive user experience
- Real-time theme updates without requiring app restart
- Persistent color selection saved per album in database
- Dynamic theme updates affecting buttons, sliders, and UI elements
- Available in both album details and saved album pages

#### Code Architecture & Data Management
- **Album Migration Utility**: New dedicated utility for converting albums from legacy format to new format with `format_version: 2`
- Automatic database schema migration with `format_version` column creation when needed
- Clean separation of concerns between debugging, migration, and JSON repair functionality

### Improved

#### Settings & Debug Tools
- **Cleaned Debug Utility**: Streamlined `DebugUtil` to focus solely on debugging and diagnostic reporting
- Removed migration logic from debug tools and moved to dedicated `AlbumMigrationUtility`
- Enhanced settings page organization with dedicated "Convert Albums to New Format" button
- **Simplified Database Operations**: Removed unused `JsonFixer` class that was causing confusion

#### Data Architecture
- Clear distinction between album format migration and database cleanup operations
- Enhanced album conversion process with proper metadata preservation and format validation

### Fixed

#### Share Widget & Rating Display
- Fixed ShareWidget to display all track ratings including zero ratings with proper app color theming
- Enhanced ShareWidget to use selected dominant colors from album details pages
- Fixed track rating metadata attachment to ensure proper rating display in share images
- Improved rating color consistency between main app and share widget display
- Fixed ShareWidget rating extraction to prioritize track metadata over ratings map

#### Custom Lists & UI
- Fixed custom lists page not refreshing after exiting full list reordering mode
- Improved UI refresh behavior when saving custom list order to ensure immediate visual feedback
- Enhanced reordering mode state management to properly reload lists after order changes

#### Theme System & Color Management
- Fixed primary color updates now propagate correctly across the entire application
- Resolved theme service synchronization issues preventing color changes from applying consistently
- Enhanced color notification system to ensure all UI components receive theme updates immediately
- Fixed color picker dialog properly updating all app screens when new colors are selected
- Improved theme state management to prevent color reversion during app navigation

#### Album Format Migration
- Fixed album migration to properly update both JSON `data` field and database column with `format_version: 2`
- Enhanced migration detection to check actual data format rather than just column values
- Fixed database constraints during migration by ensuring `format_version` column exists before updates

## [1.1.2-1] - 2025-05-12

### Added
- Implemented clean architecture project structure with clear separation of concerns
- Organized code into feature modules and layers for better maintainability
- Added comprehensive project structure diagram in documentation
- Restructured project with core, features, platforms, ui, database, and navigation layers
- Created export files for backward compatibility during transition
- Implemented album reordering feature in saved albums page with drag-and-drop functionality
- Added dedicated reordering mode with clear visual indicators and improved user feedback
- Enhanced UI with direct feedback during reordering operations
- Added ability to save custom album order to database with proper persistence

### Improved
- Better code organization with domain-driven structure
- Clearer separation between UI and business logic
- Enhanced module boundaries with feature-based organization
- Improved maintainability through standardized project structure
- Simplified navigation and dependency management
- Reduced coupling between modules through proper abstractions
- Better testability with cleaner component isolation
- Implemented responsive design with 95% width on mobile and 85% width on desktop
- Added horizontal scrolling for tracklists to improve usability on smaller screens
- Fixed search bar alignment and overflow issues across different device sizes
- Optimized layout for various screen sizes with consistent width constraints
- Enhanced platform icon display with improved overflow handling

### Fixed

#### Data Management & Import
- Fixed UNIQUE constraint violations when importing album-list relationships in backup files
- Enhanced import process to properly handle duplicate entries in custom lists
- Improved error handling during backup import to ensure all data is properly processed
- Added better logging for database constraints during import operations
- Fixed duplicate method definitions in DatabaseHelper
- Removed unused code in custom lists page

#### UI & Navigation
- Enhanced custom list and saved albums reordering with improved drag-and-drop handling and state persistence
- Enhanced drag handle positioning for better user experience
- Implemented consistent UI for reordering between custom lists and saved albums pages
- Enhanced color_reset_utility to properly update theme service
- Added better error handling and diagnostics
- Fixed search bar alignment and width issues on both mobile and desktop platforms
- Added responsive width handling across all app screens (95% on mobile, 85% on desktop)
- Implemented horizontal scrolling for tracklists to prevent overflow on narrow screens
- Optimized platform icon display with proper overflow handling

#### Theme System
- Ensured theme color and mode now update correctly when importing backups
- Fixed theme color updating properly when imported from backup
- Added updateThemeModeFromImport to ThemeService
- Ensured primary color correctly persists across app restarts
- Improved settings page UI updates for theme changes

#### Platform Integration
- Fixed platform match widget causing Bandcamp icons not to be properly highlighted when selected
- Fixed concurrent modification issues in platform match widget causing Discogs icons not to appear
- Fixed platform icon selection logic to properly handle Bandcamp URLs with different domain formats
- Improved platform matching with more reliable URL detection and platform identification
- Fixed missing platform icons by ensuring all standard platforms are always included in supported platforms list
- Enhanced platform URL detection and matching with consistent logging and error handling

## [1.1.1-1] - 2025-05-07

### Album Notes & Documentation
- Added album notes feature for saving personal reviews, thoughts, and observations
- Implemented notes display and editing on album details page
- Added copy functionality for easy sharing of album notes
- Positioned notes section below tracklist for better user experience
- Added tooltip support for notes with copy functionality
- Implemented consistent note display across saved albums and details pages
- Added delete functionality for album notes with confirmation dialog

### Album Date Management System
- Added comprehensive date fixing utility in settings with UI for batch fixing missing dates
- Fixed Deezer album date handling to prevent null dates and avoid placeholder fallbacks
- Enhanced date extraction and persistence across all supported music platforms
- Implemented unified album data format for consistent storage and retrieval
- Added direct API integration with improved error recovery for accurate release date retrieval
- Enhanced tooltip support throughout the app for better accessibility
- Fixed BuildContext handling across async gaps for improved app stability
- Fixed placeholder dates being displayed instead of "Unknown Date" when date information is missing
- Implemented proper detection of placeholder dates (Jan 1, 2000) to display as "Unknown Date"
- Added multi-level date extraction system that checks multiple sources for maximum reliability
- Implemented comprehensive logging for date parsing to improve troubleshooting
- Added better error recovery for various date formats across different music platforms
- Comprehensive Bandcamp date parsing for non-standard formats including "11 Oct 2024 00:00:00 GMT"
- Fixed runtime exceptions when parsing non-standard date formats
- Fixed year-only date handling for Discogs releases
- Fixed timezone issues in date parsing for consistent display across devices
- Enhanced date validation with appropriate fallbacks for missing or corrupted dates
- Fixed future release date handling with metadata preservation
- Fixed search results date sorting for Deezer albums with missing dates

### Custom List & UI Improvements
- Custom list order persistence across app restarts
- Improved list management with drag-to-reorder functionality
- Reduced verbose logging in dialog list rendering for better performance
- Changed custom list dialog to use ordered lists instead of alphabetical sorting
- Custom list ordering now properly saves and loads from database
- Lists now maintain the user-defined order consistently throughout the app
- Fixed list reordering persistence issue in custom album lists
- Implemented proper album order synchronization with database
- Fixed custom lists appearing in wrong order in "Save Album" dialogs
- Ensured consistent ordering across all list selection interfaces
- Custom lists reordering with drag handles at consistent leftmost position
- Common layout for album cards across the app for better visual consistency
- Fixed drag and drop functionality in custom lists and saved albums
- Removed duplicate drag handles to avoid UI clutter and overlap with icons
- Corrected drag handle positioning in list and album views
- Consistent 85% width design pattern across all UI components
- Consistent notification styling with 85% width to match app theme

### Album Data & Metadata Management
- Standardized album data format between different music platforms
- Enhanced album model to user data conversion for reliable storage
- Fixed album details page to properly save and retrieve complete album metadata
- Improved error recovery when processing album data with missing fields
- Enhanced metadata extraction with redundant storage for maximum reliability
- Multi-level metadata extraction from various album data sources for maximum reliability
- Fixed critical issue with album release dates not being preserved in database storage
- Improved Deezer album data handling with consistent fields
- Standardized artwork field naming for consistent display
- Fixed inconsistent release date display with proper formatting
- Fixed Bandcamp album metadata storage with proper track information preservation
- Fixed track persistence for albums from all supported platforms
- Improved track metadata persistence with consistent field naming
- Enhanced album artwork URL extraction with comprehensive logging

### Database & Data Persistence
- Fixed Linux window title bar not displaying on GTK-based systems
- Optimized database queries with better error handling
- Complete migration from SharedPreferences to SQLite database for all settings and user data
- New database architecture providing better performance, reliability and data integrity
- Backward compatibility with previous versions through guided migration process
- Extensive logging and error handling for diagnosing database issues
- Implementation of transaction support for data consistency
- Database maintenance tools including vacuum, integrity checks, and emergency reset
- Cross-platform data migration with progress tracking
- Recovery mechanisms for database connection issues
- New database helper methods for settings management
- Centralized version tracking with version_info.dart
- Automatic migration of remaining SharedPreferences data
- Final cleanup utility for SharedPreferences
- Database integrity verification and repair tools
- Enhanced album ID handling for cross-platform compatibility
- Improved error recovery for database operations
- Support for backup and restore of all settings
- Database migration utility with progress tracking
- Database integrity checking and vacuum optimization
- More reliable track ID handling with position-based fallbacks

### Platform Integration & Middleware
- Optimized platform match widget with progressive loading for immediate UI feedback
- Implemented memory caching system with 30-day TTL for faster repeat album views
- Added waterfall loading strategy (memory cache → database → API) for optimal performance
- Parallelized platform API requests for significantly faster matching
- Improved platform matching with immediate visual feedback using skeleton loading
- Added focused logging for platform match operations with key performance metrics
- Reduced redundant verification of previously validated platform matches
- Fixed platform match widget lifecycle issues to prevent setState after dispose
- Added proper component disposal handling to platform match queries
- Improved error resilience in platform match component with mounted state checks
- Fixed control flow issues in async operations for better stability
- Implemented middleware architecture for Deezer albums to efficiently fetch accurate release dates and track information
- New DeezerMiddleware class matching the pattern used for Discogs to enhance album data
- Fixed Deezer album date loading with efficient on-demand fetching strategy
- Improved Deezer search performance by fetching dates only when needed
- Fixed Deezer album integration with dedicated middleware for better performance and accuracy
- Solved performance issues in Deezer album date loading by using on-demand middleware approach
- Added 'useDeezerMiddleware' flag for identifying albums requiring date enhancement
- Improved Deezer date loading with proper error recovery mechanisms
- New platform match cleaner utility for fixing incorrect platform associations
- Improved URL matching between streaming platforms with unified matching algorithms
- Standardized matching thresholds across all music platforms (Spotify, Apple Music, Deezer, Discogs)
- Fixed platform match widget with improved stability and reliability
- Fixed unstable URL pasting, particularly for Discogs and Bandcamp URLs
- Normalized similarity thresholds across all platform services for consistent matching quality
- Enhanced platform-specific URL handling for Bandcamp and Discogs URLs
- Middleware architecture for platform-specific album enhancement
- Implemented consistent platform matching mechanisms across all music services
- Created dedicated platform_match_cleaner component for user-initiated match fixing

### Discogs Integration
- Comprehensive Discogs integration with middleware for advanced album processing
- Improved handling for both Discogs master and release album types
- Consistent metadata extraction across all Discogs API interactions
- Reliable credential management system for Discogs API with database storage
- Fixed Discogs track duration fetching with intelligent version selection
- Improved Discogs date parsing with background prefetching for search results
- Robust date parsing for Discogs releases with intelligent fallbacks
- Complete overhaul of Discogs integration with proper error handling
- Fixed Discogs URL detection for both master and release album types
- Fixed inconsistent metadata extraction between search and direct URL flows
- Improved credential management for Discogs API with database-first approach
- Fixed Discogs album URL detection and metadata extraction
- Improved Discogs version selection logic to find best release dates
- Fixed master/release relationship handling for Discogs albums
- Enhanced release date processing with multi-attempt parsing strategies
- Comprehensive track duration detection for Discogs albums across all available versions
- Smart version selection for Discogs albums based on format, country, and data quality
- Discogs integration with complete search and album details support
- Added consistent credential retrieval system with primary and fallback sources
- Implemented intelligent Discogs version scoring system based on release formats and countries
- Created multi-pass approach to finding accurate Discogs dates from related releases

### Theme & UI Improvements
- Complete overhaul of app theming with new ThemeService architecture
- Centralized theme management with reactive updates across the app
- Support for dynamic theme and color changes without app restart
- Fixed critical color corruption issues with proper color value handling
- Fixed hex color representation issues ensuring consistent RGB to hex conversion
- Fixed color picker issues with direct integer-based RGB handling
- Support for dark mode, light mode and system default with seamless transitions
- Fixed black color issue on Android devices with proper "safe black" implementation
- Eliminated flashing of default purple color during app startup with theme preloading
- Proper color persistence across app restarts
- Custom hex color input field in color picker for precise color selection
- Interactive color preview in settings for immediate feedback
- Critical issue with color picker not displaying correct hex values for selected colors
- Fixed RGB to hex conversion ensuring exact values are preserved across the application
- Fixed variable usage in color handling to prevent duplicate definitions
- Critical color handling issues with reliable RGB value storage and retrieval
- Theme consistency issues with proper state management and persistence
- Settings page color picker corruption with proper color value normalization
- Race condition in ThemeService preventing proper theme application
- Fixed notification issues with standardized 85% width for consistent UI
- Eliminated corrupted colors (particularly black and near-black colors) through proper value handling
- Fixed color selection in settings page to always use correct color channels
- SVG-based platform icons with proper theme support

### API & Search Features
- Secure user-provided API key support for Spotify and Discogs services
- Dedicated API key management section in the Settings page
- Automatic API key validation for Spotify credentials
- Detailed API setup instructions with step-by-step guidance
- Clear status indicators showing connected API services
- Helpful context for why certain services require API keys
- Direct links to developer portals for obtaining API credentials
- Fixed Spotify and Discogs search results showing only when API keys are provided
- Enhanced API key persistence using secure database storage
- Fixed platform-specific search behavior when API keys are missing
- Improved error handling for failed API authentication attempts
- Fixed user-facing API documentation links
- Implemented API key validation system with proper error handling
- Added conditional search behavior based on available credentials
- Implemented platform-specific configuration UI components
- Enhanced service factory to handle authentication failures gracefully

### Album Features & Cross-platform Compatibility
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
- Default search platform selection in settings
- Default search platform persistence across app restarts
- Multi-platform search capability (iTunes, Spotify, Deezer)
- Enhanced clipboard detection for URLs from all supported platforms
- Improved clipboard URL detection and handling across all supported platforms
- Better platform detection from pasted URLs with more accurate source identification
- Enhanced album metadata extraction from Bandcamp URLs
- Platform icons in search results for better visual identification
- Platform-specific search capabilities for more accurate results
- Global notifications system for real-time app state updates

### Brand & Application Assets
- Designed and implemented a new modern logo for better brand identity
- Created optimized logo assets for all supported platforms (Android, iOS, Windows, macOS, Linux)
- Implemented adaptive icon support for Android with proper foreground/background layers
- Added high-resolution icons for desktop platforms with proper scaling
- Updated app icon in package manifests for all platforms
- Ensured proper icon display in OS task managers and app launchers
- Optimized SVG source files for better scaling and rendering
- Created platform-specific variants to match OS design guidelines
- Improved support option in About dialog
- Enhanced footer with version information and sponsor links
- Refined database maintenance tools with appropriate icons
- Emergency reset option for critical database issues

### Performance & Logging Improvements
- Fixed overly verbose logging with cleaner, more organized log output
- Removed unnecessary background processing in middleware for improved performance
- Improved log management with reduced verbosity and better organization
- Fixed redundant artwork URL logging during album display
- Optimized logging for better debug experience and reduced noise
- Eliminated duplicate artwork URL lookups and logs
- Fixed performance issues related to excessive logging
- Streamlined logging for album loading to prevent redundant messages
- Fixed album conversion using appropriate JsonFixer implementation
- Fixed duplicate functionality for Bandcamp album updating and album format conversion
- Platform-specific path issues for data storage
- Proper disposal of resources to prevent memory leaks
- Improved state handling for asynchronous operations
- Added artwork URL caching during album processing for better performance
- Implemented efficient artwork URL extraction across multiple data source formats
- Added data summary logging for better troubleshooting
- Improved logging consistency with single-responsibility pattern
- Enhanced saved albums display with optimized artwork detection and handling
- Reduced debug log noise by eliminating redundant messages
- Added log summaries for batch operations to improve monitoring
- Implemented pre-processed data storage to avoid redundant lookups
- Added consistent notification formatting for better UX
- Improved SnackBar appearance with standardized width
- Enhanced sponsor integration for better project support options

### Code Quality & Architecture
- Enhanced logging organization with consistent message formats
- Reduced log verbosity by eliminating redundant messages
- Added log filtering to focus on important diagnostic information
- Standardized platform URL detection patterns for better URL handling
- Added requiresMiddlewareProcessing flag for advanced metadata extraction
- Created specialized date parsers for each music platform's unique format
- Enhanced date fallback mechanism with consistent default values
- Created utility functions for date normalization and standardization
- Enhanced DateFormat usage with explicit locale support
- Improved RegExp patterns for date extraction from complex strings
- Added manual date component parsing for maximum flexibility
- Added extensive validation and error recovery for date parsing operations
- Enhanced clipboard integration with improved URL format detection
- Improved album metadata extraction pipeline with better error handling
- Added comprehensive date format conversion utilities
- Implemented special case handling for problematic date formats
- Enhanced logging for date parsing to aid in debugging
- Implemented secure API key storage in SQLite database
- Created centralized ApiKeys and ApiKeyManager classes for better credential management
- Centralized album name normalization with regex-based suffix detection
- Standardized string comparison utilities for better text matching
- Platform-agnostic album title cleanup system
- Improved platform service factory with better error handling
- Improved BuildContext management with GlobalKey approach
- Added StreamController-based global notification system
- Enhanced error logging for platform-specific issues
- Better album matching algorithms for cross-platform compatibility
- Optimized search queries with improved platform handling
- Connected track ratings with SQLite database storage for persistent ratings
- Added position-based track ID matching for ratings when direct ID match fails
- Fixed recursive method calls causing stack overflow errors in rating display
- Implemented robust track metadata saving with ratings in database
- Added reliable fallback mechanisms when track data is incomplete
- Added extensive debug logging for rating matching and persistence

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
