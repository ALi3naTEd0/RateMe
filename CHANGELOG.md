# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Nix flakes support for better NixOS integration
- Development shell for NixOS users

### Changed
- Enhanced NixOS packaging with better runtime dependencies
- Refactored AppVersionFooter to dynamically load app version information
- Moved About dialog functionality from main.dart to footer.dart for better code organization

### Fixed
- NixOS runtime library paths and dependencies
- Improved iTunes search album labeling with cleaner format: show "(Clean)" instead of "[Clean]" only for clean versions
- Removed redundant "[Deluxe]" labels from search results when the title already includes "Deluxe"
- Updated About dialog to display correct app version and license information
- Centralized version display in AppVersionFooter to avoid duplicated information

### Development
- Added development shell with all required dependencies for NixOS
- Improved build reproducibility with flake.lock

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

### Fixed
- Fixed Android app not launching on some devices
- Fixed track filtering to exclude videos from iTunes results
- Fixed portable Windows package structure with data directory
- Fixed release workflow for proper version propagation
- Icon visibility in Arch Linux package
- GTK dependencies in Flatpak package
- Desktop entry consistency across all Linux distributions
- Missing exclamation mark in application name

## [1.0.4-3] - 2025-07-15

### Fixed
- Fixed Android app not launching on some devices
- Fixed track filtering to exclude videos from iTunes results
- Fixed portable Windows package structure with data directory
- Improved version management and documentation
- Fixed release workflow for proper version propagation

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
