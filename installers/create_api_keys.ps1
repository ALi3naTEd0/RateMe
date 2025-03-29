param(
    [string]$SpotifyClientId,
    [string]$SpotifyClientSecret
)

# Create lib directory if it doesn't exist
New-Item -Path "lib" -ItemType Directory -Force | Out-Null

# Create API keys content
$content = @"
// API Keys for external services
class ApiKeys {
  // Spotify API Credentials
  static const String spotifyClientId = '$SpotifyClientId';
  static const String spotifyClientSecret = '$SpotifyClientSecret';
}
"@

# Write to file
$filePath = Join-Path -Path $PWD -ChildPath "lib\api_keys.dart"
[System.IO.File]::WriteAllText($filePath, $content)

# Verify file was created
if (Test-Path "lib\api_keys.dart") {
    Write-Host "API keys file created successfully at: $filePath"
    Get-Content -Path "lib\api_keys.dart" -TotalCount 5
    return 0
} else {
    Write-Error "Failed to create API keys file"
    return 1
}
