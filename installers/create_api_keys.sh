#!/bin/bash

# This script works both in GitHub Actions and local builds
# It parallels the PowerShell script for Windows builds

# In GitHub Actions, secrets are passed from the workflow
# For local builds, use environment variables

# Read keys from environment variables (same as GitHub Actions would use)
CLIENT_ID="${SPOTIFY_CLIENT_ID}"
CLIENT_SECRET="${SPOTIFY_CLIENT_SECRET}"

# If running in GitHub Actions, use secrets directly
if [ -n "$GITHUB_ACTIONS" ]; then
    echo "Running in GitHub Actions environment"
    # GitHub Actions will provide these as environment variables
else
    echo "Running in local build environment"
    # For local builds, either use environment variables or provide defaults
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        echo "Warning: Spotify API credentials not provided via environment variables"
        echo "Using placeholder values - app functionality will be limited"
        CLIENT_ID="PLACEHOLDER_ID"
        CLIENT_SECRET="PLACEHOLDER_SECRET"
    fi
fi

echo "Creating API keys file with provided credentials"

# Create the API keys file
mkdir -p lib
cat > lib/api_keys.dart << EOF
// Generated API keys file - DO NOT COMMIT TO VERSION CONTROL
class ApiKeys {
  static const String spotifyClientId = '$CLIENT_ID';
  static const String spotifyClientSecret = '$CLIENT_SECRET';
}
EOF

echo "API keys file created successfully"
