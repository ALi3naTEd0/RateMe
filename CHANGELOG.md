# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Flatpak package support for Linux
- Full GTK theme support in all Linux packages
- Nix flakes support for better NixOS integration
- Development shell for NixOS users

### Changed
- Standardized application name to "Rate Me!" across all platforms
- Improved desktop integration for Linux packages
- Fixed icon issues in Arch Linux package
- Consistent icon naming across all Linux packages
- Enhanced NixOS packaging with better runtime dependencies
- Standardized Android package ID from com.example.rateme to com.ali3nated0.rateme
  Note: This will cause a one-time duplicate installation. Future updates will work normally.

### Fixed
- Icon visibility in Arch Linux package
- GTK dependencies in Flatpak package
- Desktop entry consistency across all Linux distributions
- Missing exclamation mark in application name
- NixOS runtime library paths and dependencies

### Development
- Added development shell with all required dependencies for NixOS
- Improved build reproducibility with flake.lock
- Better cross-distribution compatibility through standardized packaging

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
