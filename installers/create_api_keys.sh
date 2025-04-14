#!/bin/bash

# This script works both in GitHub Actions and local builds
# It parallels the PowerShell script for Windows builds

# In GitHub Actions, secrets are passed from the workflow
# For local builds, use environment variables

# Read keys from environment variables (same as GitHub Actions would use)
SPOTIFY_ID="${SPOTIFY_CLIENT_ID}"
SPOTIFY_SECRET="${SPOTIFY_CLIENT_SECRET}"
DISCOGS_KEY="${DISCOGS_CONSUMER_KEY}"
DISCOGS_SECRET="${DISCOGS_CONSUMER_SECRET}"

# If running in GitHub Actions, use secrets directly
if [ -n "$GITHUB_ACTIONS" ]; then
    echo "Running in GitHub Actions environment"
    # GitHub Actions will provide these as environment variables
else
    echo "Running in local build environment"
    # For local builds, either use environment variables or provide defaults
    if [ -z "$SPOTIFY_ID" ] || [ -z "$SPOTIFY_SECRET" ]; then
        echo "Warning: Spotify API credentials not provided via environment variables"
        echo "Using placeholder values - app functionality will be limited"
        SPOTIFY_ID="PLACEHOLDER_ID"
        SPOTIFY_SECRET="PLACEHOLDER_SECRET"
    fi
    
    if [ -z "$DISCOGS_KEY" ] || [ -z "$DISCOGS_SECRET" ]; then
        echo "Warning: Discogs API credentials not provided via environment variables"
        echo "Using placeholder values - app functionality will be limited"
        DISCOGS_KEY="PLACEHOLDER_DISCOGS_KEY"
        DISCOGS_SECRET="PLACEHOLDER_DISCOGS_SECRET"
    fi
fi

echo "Creating API keys file with provided credentials"

# Create the API keys file
mkdir -p lib
cat > lib/api_keys.dart << EOF
// Generated API keys file - DO NOT COMMIT TO VERSION CONTROL
import 'dart:convert';

class ApiKeys {
  // Spotify API Credentials
  static const String spotifyClientId = '$SPOTIFY_ID';
  static const String spotifyClientSecret = '$SPOTIFY_SECRET';
  
  // Discogs API Credentials
  static const String discogsConsumerKey = '$DISCOGS_KEY';
  static const String discogsConsumerSecret = '$DISCOGS_SECRET';
  
  // Method to get Spotify auth token
  static String getSpotifyToken() {
    return base64.encode(utf8.encode('\$spotifyClientId:\$spotifyClientSecret'));
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
EOF

echo "API keys file created successfully"
