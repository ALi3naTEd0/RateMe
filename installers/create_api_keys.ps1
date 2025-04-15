param(
    [string]$SpotifyClientId,
    [string]$SpotifyClientSecret,
    [string]$DiscogsConsumerKey,
    [string]$DiscogsConsumerSecret
)

# Create lib directory if it doesn't exist
New-Item -Path "lib" -ItemType Directory -Force | Out-Null

# Create API keys content
$content = @"
// Generated API keys file - DO NOT COMMIT TO VERSION CONTROL
import 'dart:convert';

class ApiKeys {
  // Spotify API Credentials
  static const String spotifyClientId = '$SpotifyClientId';
  static const String spotifyClientSecret = '$SpotifyClientSecret';
  
  // Discogs API Credentials
  static const String discogsConsumerKey = '$DiscogsConsumerKey';
  static const String discogsConsumerSecret = '$DiscogsConsumerSecret';
  
  // Method to get Spotify auth token
  static String getSpotifyToken() {
    return base64.encode(utf8.encode(spotifyClientId + ':' + spotifyClientSecret));
  }
  
  // API request timeout durations (in seconds)
  static const int defaultRequestTimeout = 30;
  static const int longRequestTimeout = 60;
  
  // Rate limiting configuration
  static const int maxRequestsPerMinute = 120;
  static const int cooldownPeriodSeconds = 60;
}

class ApiEndpoints {
  // Spotify endpoints
  static const String spotifyAlbumSearch = 'search';
  static const String spotifyAlbumDetails = 'albums';
  static const String spotifyArtistDetails = 'artists';
  
  // Discogs endpoints
  static const String discogsSearch = 'database/search';
  static const String discogsMaster = 'masters';
  static const String discogsRelease = 'releases';
}
"@

# Write to file
$filePath = Join-Path -Path $PWD -ChildPath "lib\api_keys.dart"
[System.IO.File]::WriteAllText($filePath, $content)

# Verify file was created
if (Test-Path "lib\api_keys.dart") {
    Write-Host "API keys file created successfully at: $filePath"
    Write-Host "First few lines (with keys hidden):"
    Get-Content -Path "lib\api_keys.dart" -TotalCount 5 | ForEach-Object { 
        $_ -replace "'[^']*'", "'***'" 
    }
    return 0
} else {
    Write-Error "Failed to create API keys file"
    return 1
}
