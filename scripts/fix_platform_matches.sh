#!/bin/bash
# Script to fix platform matches for specific albums in the RateMe app database

# Set the path to the SQLite database file
DB_PATH="/home/x/Documents/rateme.db"

# Check if sqlite3 is installed
if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 is not installed. Please install it first."
    exit 1
fi

# Function to list available databases
list_available_databases() {
    echo "Searching for SQLite databases in common locations..."
    
    # Common locations to search
    LOCATIONS=(
        "/home/x/RateMe"
        "/home/x/Documents"
        "/home/x/.local/share/RateMe"
        "/home/x"
        "/home/x/Downloads"
    )
    
    for location in "${LOCATIONS[@]}"; do
        if [ -d "$location" ]; then
            echo "Searching in $location..."
            find "$location" -name "*.db" -type f -not -path "*/\.*" | grep -i "rateme\|music\|album"
        fi
    done
    
    echo ""
    echo "If your database is in another location, please edit the script and set DB_PATH."
    echo "Current DB_PATH is: $DB_PATH"
    echo ""
    read -p "Would you like to specify a different database path? (y/n): " change_path
    
    if [ "$change_path" = "y" ]; then
        read -p "Enter the full path to your database file: " new_path
        if [ -f "$new_path" ]; then
            DB_PATH="$new_path"
            echo "Database path updated to: $DB_PATH"
        else
            echo "File not found: $new_path"
            echo "Keeping current path: $DB_PATH"
        fi
    fi
}

# Add a new function at the beginning of the script
check_database() {
    if [ ! -f "$DB_PATH" ]; then
        echo "Error: Database file not found at $DB_PATH"
        list_available_databases
        return 1
    fi
    
    # Verify this is actually a SQLite database
    if ! sqlite3 "$DB_PATH" "PRAGMA database_list;" &>/dev/null; then
        echo "Error: The file at $DB_PATH doesn't appear to be a valid SQLite database."
        list_available_databases
        return 1
    fi
    
    # Check if the required tables exist
    ALBUMS_TABLE=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='albums';")
    MATCHES_TABLE=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='platform_matches';")
    
    if [ "$ALBUMS_TABLE" -eq "0" ] || [ "$MATCHES_TABLE" -eq "0" ]; then
        echo "Error: Required tables 'albums' or 'platform_matches' not found in the database."
        echo "Is this the correct RateMe database?"
        return 1
    fi
    
    # Database looks good
    echo "Database verified: $DB_PATH"
    return 0
}

# Call the check_database function before showing the menu
if ! check_database; then
    exit 1
fi

echo "RateMe Database Platform Match Fix"
echo "=================================="
echo

# Function to list all Discogs albums
list_discogs_albums() {
    echo "Listing all Discogs albums in your database:"
    echo "----------------------------------------"
    sqlite3 "$DB_PATH" "
    SELECT 
        id, 
        name, 
        artist, 
        url 
    FROM 
        albums 
    WHERE 
        platform = 'discogs' OR url LIKE '%discogs.com%'
    ORDER BY 
        artist, name;
    " | while read -r line; do
        echo "$line" | awk -F '|' '{printf "ID: %-10s %-30s %-30s URL: %s\n", $1, $3, $2, $4}'
    done
    
    echo
    echo "Found $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM albums WHERE platform = 'discogs' OR url LIKE '%discogs.com%'") Discogs albums"
    echo
}

# Function to fix Kink - Tsunami matches
fix_kink_tsunami() {
    echo "Fixing Kink - Tsunami platform matches..."
    
    # List all albums first so user can see the IDs
    list_discogs_albums
    
    # First, find the album ID - use a more flexible query
    ALBUM_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM albums WHERE 
                (name LIKE '%Tsunami%' AND artist LIKE '%Kink%') OR 
                (url LIKE '%discogs.com%2659820%') OR
                (url LIKE '%discogs.com%master%') AND (name LIKE '%Tsunami%')
                LIMIT 1;")
    
    if [ -z "$ALBUM_ID" ]; then
        echo "Could not find Kink - Tsunami album automatically."
        echo "Please enter the album ID from the list above:"
        read -p "Album ID: " ALBUM_ID
        
        if [ -z "$ALBUM_ID" ]; then
            echo "No ID provided. Exiting."
            return
        fi
    fi
    
    echo "Found album with ID: $ALBUM_ID"
    
    # Show album details
    echo "Album details:"
    sqlite3 "$DB_PATH" "SELECT id, name, artist, platform, url FROM albums WHERE id = '$ALBUM_ID';"
    
    # Show current platform matches
    echo "Current platform matches:"
    sqlite3 "$DB_PATH" "SELECT platform, url FROM platform_matches WHERE album_id = '$ALBUM_ID';"
    
    # Ask for confirmation before deleting
    read -p "Delete existing platform matches for this album? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Operation cancelled."
        return
    fi
    
    # Delete existing platform matches
    sqlite3 "$DB_PATH" "DELETE FROM platform_matches WHERE album_id = '$ALBUM_ID';"
    echo "Deleted all existing platform matches for album ID $ALBUM_ID"
    
    # Ensure we keep the Discogs URL (using the URL from the album table)
    DISCOGS_URL=$(sqlite3 "$DB_PATH" "SELECT url FROM albums WHERE id = '$ALBUM_ID';")
    
    if [ ! -z "$DISCOGS_URL" ]; then
        echo "Restoring Discogs URL: $DISCOGS_URL"
        CURRENT_TIME=$(date -Iseconds)
        
        sqlite3 "$DB_PATH" "INSERT INTO platform_matches (album_id, platform, url, verified, timestamp) 
                           VALUES ('$ALBUM_ID', 'discogs', '$DISCOGS_URL', 1, '$CURRENT_TIME');"
        
        echo "Restored Discogs platform match. Other platforms will be re-searched on next app launch."
    fi
    
    echo "Fix completed. Please restart the app to re-search for matches on other platforms."
}

# Function to delete all platform matches
delete_all_platform_matches() {
    echo "WARNING: This will delete ALL platform matches in the database."
    read -p "Are you sure you want to proceed? (y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        echo "Operation cancelled."
        return
    fi
    
    echo "Deleting all platform matches..."
    sqlite3 "$DB_PATH" "DELETE FROM platform_matches;"
    echo "All platform matches have been deleted."
    echo "The app will search for matches again when albums are viewed."
}

# Function to list albums with platform mismatches
list_platform_mismatches() {
    echo "Looking for potential platform mismatches..."
    
    # This query finds albums where the platform in album table doesn't match any platform_matches entry
    sqlite3 "$DB_PATH" "
    SELECT 
        a.id, 
        a.name, 
        a.artist, 
        a.platform, 
        GROUP_CONCAT(pm.platform, ', ') as matched_platforms
    FROM 
        albums a
    LEFT JOIN 
        platform_matches pm ON a.id = pm.album_id
    GROUP BY 
        a.id
    HAVING 
        matched_platforms NOT LIKE '%' || a.platform || '%' AND matched_platforms IS NOT NULL;
    "
}

# Function to search albums by name or artist
search_albums() {
    read -p "Enter search term (album name or artist): " search_term
    
    if [ -z "$search_term" ]; then
        echo "No search term provided. Returning to main menu."
        return
    fi
    
    echo "Searching for albums matching: '$search_term'"
    echo "----------------------------------------"
    
    sqlite3 "$DB_PATH" "
    SELECT 
        id, 
        name, 
        artist, 
        platform,
        url 
    FROM 
        albums 
    WHERE 
        name LIKE '%$search_term%' OR artist LIKE '%$search_term%'
    ORDER BY 
        artist, name;
    " | while read -r line; do
        echo "$line" | awk -F '|' '{printf "ID: %-10s %-30s %-30s Platform: %-15s URL: %s\n", $1, $3, $2, $4, $5}'
    done
    
    echo
    read -p "Enter an album ID to see its platform matches (or press Enter to continue): " album_id
    
    if [ ! -z "$album_id" ]; then
        echo "Platform matches for album ID $album_id:"
        sqlite3 "$DB_PATH" "
        SELECT platform, url, verified, timestamp
        FROM platform_matches
        WHERE album_id = '$album_id'
        ORDER BY platform;
        " | while read -r line; do
            echo "$line" | awk -F '|' '{printf "Platform: %-15s Verified: %-5s Date: %-25s URL: %s\n", $1, $3, $4, $2}'
        done
        
        read -p "Would you like to fix matches for this album? (y/n): " fix_album
        if [ "$fix_album" = "y" ]; then
            fix_album_matches "$album_id"
        fi
    fi
}

# Function to fix matches for any album
fix_album_matches() {
    local album_id=$1
    
    if [ -z "$album_id" ]; then
        read -p "Enter album ID to fix: " album_id
    fi
    
    if [ -z "$album_id" ]; then
        echo "No album ID provided. Exiting."
        return
    fi
    
    # Show album details
    echo "Album details:"
    sqlite3 "$DB_PATH" "SELECT id, name, artist, platform, url FROM albums WHERE id = '$album_id';"
    
    # Show current platform matches
    echo "Current platform matches:"
    sqlite3 "$DB_PATH" "SELECT platform, url FROM platform_matches WHERE album_id = '$album_id';"
    
    # Ask for confirmation before deleting
    read -p "Delete existing platform matches for this album? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Operation cancelled."
        return
    fi
    
    # Delete existing platform matches
    sqlite3 "$DB_PATH" "DELETE FROM platform_matches WHERE album_id = '$album_id';"
    echo "Deleted all existing platform matches for album ID $album_id"
    
    # Get the platform of the album
    ALBUM_PLATFORM=$(sqlite3 "$DB_PATH" "SELECT platform FROM albums WHERE id = '$album_id';")
    ALBUM_URL=$(sqlite3 "$DB_PATH" "SELECT url FROM albums WHERE id = '$album_id';")
    
    if [ ! -z "$ALBUM_URL" ] && [ ! -z "$ALBUM_PLATFORM" ]; then
        echo "Restoring $ALBUM_PLATFORM URL: $ALBUM_URL"
        CURRENT_TIME=$(date -Iseconds)
        
        sqlite3 "$DB_PATH" "INSERT INTO platform_matches (album_id, platform, url, verified, timestamp) 
                           VALUES ('$album_id', '$ALBUM_PLATFORM', '$ALBUM_URL', 1, '$CURRENT_TIME');"
        
        echo "Restored $ALBUM_PLATFORM platform match. Other platforms will be re-searched on next app launch."
    fi
    
    echo "Fix completed. Please restart the app to re-search for matches on other platforms."
}

# Function to manually add platform matches for an album
manually_add_platform_matches() {
    echo "Manually Add Platform Matches"
    echo "============================"
    echo
    echo "This function will help you manually add correct platform matches for an album."
    echo
    
    # First, identify the album
    read -p "Enter part of album name or artist name to search for: " search_term
    
    if [ -z "$search_term" ]; then
        echo "No search term provided. Returning to main menu."
        return
    fi
    
    echo "Searching for albums matching: '$search_term'"
    echo "----------------------------------------"
    
    # Show matching albums
    sqlite3 "$DB_PATH" "
    SELECT 
        id, 
        name, 
        artist, 
        platform,
        url 
    FROM 
        albums 
    WHERE 
        name LIKE '%$search_term%' OR artist LIKE '%$search_term%'
    ORDER BY 
        artist, name
    LIMIT 20;
    " | while read -r line; do
        echo "$line" | awk -F '|' '{printf "ID: %-10s %-30s %-30s Platform: %-15s URL: %s\n", $1, $3, $2, $4, $5}'
    done
    
    echo
    read -p "Enter album ID to work with: " album_id
    
    if [ -z "$album_id" ]; then
        echo "No album ID provided. Returning to main menu."
        return
    fi
    
    # Show album details
    echo "Album details:"
    sqlite3 "$DB_PATH" "SELECT id, name, artist, platform, url FROM albums WHERE id = '$album_id';"
    
    # Show existing matches
    echo "Current platform matches:"
    sqlite3 "$DB_PATH" "SELECT platform, url FROM platform_matches WHERE album_id = '$album_id';"
    
    # Ask if user wants to clear existing matches
    read -p "Clear all existing platform matches for this album? (y/n): " clear_existing
    if [ "$clear_existing" = "y" ]; then
        sqlite3 "$DB_PATH" "DELETE FROM platform_matches WHERE album_id = '$album_id';"
        echo "Cleared all existing platform matches."
    fi
    
    # Now add new matches
    echo "Let's add new platform matches. For each platform, enter the correct URL or leave blank to skip."
    echo
    
    # Ensure the source platform is always added from the albums table
    ALBUM_PLATFORM=$(sqlite3 "$DB_PATH" "SELECT platform FROM albums WHERE id = '$album_id';")
    ALBUM_URL=$(sqlite3 "$DB_PATH" "SELECT url FROM albums WHERE id = '$album_id';")
    
    if [ ! -z "$ALBUM_URL" ] && [ ! -z "$ALBUM_PLATFORM" ]; then
        read -p "Keep original $ALBUM_PLATFORM URL? ($ALBUM_URL) (y/n): " keep_original
        if [ "$keep_original" = "y" ]; then
            CURRENT_TIME=$(date -Iseconds)
            
            sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO platform_matches 
                              (album_id, platform, url, verified, timestamp) 
                              VALUES ('$album_id', '$ALBUM_PLATFORM', '$ALBUM_URL', 1, '$CURRENT_TIME');"
            
            echo "Added $ALBUM_PLATFORM match."
        fi
    fi
    
    # Allow entering URLs for each platform
    platforms=("spotify" "apple_music" "deezer" "discogs")
    
    for platform in "${platforms[@]}"; do
        # Skip the platform that's already been handled above
        if [ "$platform" = "$ALBUM_PLATFORM" ] && [ "$keep_original" = "y" ]; then
            continue
        fi
        
        read -p "Enter correct $platform URL (or leave blank to skip): " platform_url
        
        if [ ! -z "$platform_url" ]; then
            CURRENT_TIME=$(date -Iseconds)
            
            sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO platform_matches 
                              (album_id, platform, url, verified, timestamp) 
                              VALUES ('$album_id', '$platform', '$platform_url', 1, '$CURRENT_TIME');"
            
            echo "Added $platform match."
        fi
    done
    
    echo
    echo "Updated platform matches:"
    sqlite3 "$DB_PATH" "SELECT platform, url FROM platform_matches WHERE album_id = '$album_id';"
    echo
    echo "Platform matches updated. Please restart the app to see the changes."
}

# Function to fix a specific match between Kink - Tsunami and its Spotify match
fix_kink_tsunami_spotify_match() {
    echo "Fixing Kink - Tsunami Spotify Match"
    echo "================================="
    echo
    
    # Find the album by searching for "Kink Tsunami"
    echo "Searching for 'Kink Tsunami' albums..."
    
    # Show matching albums
    sqlite3 "$DB_PATH" "
    SELECT 
        id, 
        name, 
        artist, 
        platform,
        url 
    FROM 
        albums 
    WHERE 
        name LIKE '%Tsunami%' AND artist LIKE '%Kink%'
    ORDER BY 
        artist, name;
    " | while read -r line; do
        echo "$line" | awk -F '|' '{printf "ID: %-10s %-30s %-30s Platform: %-15s URL: %s\n", $1, $3, $2, $4, $5}'
    done
    
    echo
    read -p "Enter album ID to fix (or press Enter to cancel): " album_id
    
    if [ -z "$album_id" ]; then
        echo "No album ID provided. Returning to main menu."
        return
    fi
    
    # Show existing matches
    echo "Current platform matches:"
    sqlite3 "$DB_PATH" "SELECT platform, url FROM platform_matches WHERE album_id = '$album_id';"
    
    # Find Spotify match
    SPOTIFY_URL=$(sqlite3 "$DB_PATH" "SELECT url FROM platform_matches WHERE album_id = '$album_id' AND platform = 'spotify';")
    
    echo "Current Spotify URL: $SPOTIFY_URL"
    
    # Correct Spotify URL for Kink - Tsunami
    CORRECT_SPOTIFY="https://open.spotify.com/album/1VJUg1HQNxgnQUvM5CymVM"
    
    read -p "Replace with correct Spotify URL? ($CORRECT_SPOTIFY) (y/n): " replace_spotify
    if [ "$replace_spotify" = "y" ]; then
        CURRENT_TIME=$(date -Iseconds)
        
        # Delete existing Spotify match
        sqlite3 "$DB_PATH" "DELETE FROM platform_matches WHERE album_id = '$album_id' AND platform = 'spotify';"
        
        # Add correct Spotify match
        sqlite3 "$DB_PATH" "INSERT INTO platform_matches 
                          (album_id, platform, url, verified, timestamp) 
                          VALUES ('$album_id', 'spotify', '$CORRECT_SPOTIFY', 1, '$CURRENT_TIME');"
        
        echo "Spotify match updated."
    fi
    
    # Ask about adding Apple Music match
    read -p "Add Apple Music match? (y/n): " add_apple
    if [ "$add_apple" = "y" ]; then
        APPLE_URL="https://music.apple.com/album/tsunami-single/1388458156"
        CURRENT_TIME=$(date -Iseconds)
        
        # Delete existing Apple Music match if any
        sqlite3 "$DB_PATH" "DELETE FROM platform_matches WHERE album_id = '$album_id' AND platform = 'apple_music';"
        
        # Add Apple Music match
        sqlite3 "$DB_PATH" "INSERT INTO platform_matches 
                          (album_id, platform, url, verified, timestamp) 
                          VALUES ('$album_id', 'apple_music', '$APPLE_URL', 1, '$CURRENT_TIME');"
        
        echo "Apple Music match added."
    fi
    
    # Ask about adding Deezer match
    read -p "Add Deezer match? (y/n): " add_deezer
    if [ "$add_deezer" = "y" ]; then
        DEEZER_URL="https://www.deezer.com/album/63666022"
        CURRENT_TIME=$(date -Iseconds)
        
        # Delete existing Deezer match if any
        sqlite3 "$DB_PATH" "DELETE FROM platform_matches WHERE album_id = '$album_id' AND platform = 'deezer';"
        
        # Add Deezer match
        sqlite3 "$DB_PATH" "INSERT INTO platform_matches 
                          (album_id, platform, url, verified, timestamp) 
                          VALUES ('$album_id', 'deezer', '$DEEZER_URL', 1, '$CURRENT_TIME');"
        
        echo "Deezer match added."
    fi
    
    echo
    echo "Updated platform matches:"
    sqlite3 "$DB_PATH" "SELECT platform, url FROM platform_matches WHERE album_id = '$album_id';"
    echo
    echo "Platform matches updated. Please restart the app to see the changes."
}

# Menu
echo "Select an option:"
echo "1) Fix Kink - Tsunami platform matches"
echo "2) Delete ALL platform matches (will be re-searched on next app launch)"
echo "3) List albums with potential platform mismatches"
echo "4) List all Discogs albums"
echo "5) Search albums by name or artist"
echo "6) Fix matches for any album by ID"
echo "7) Manually add platform matches"
echo "8) Quick-fix Kink - Tsunami Spotify match"
echo "q) Quit"
read -p "Choice: " choice

case $choice in
    1)
        fix_kink_tsunami
        ;;
    2)
        delete_all_platform_matches
        ;;
    3)
        list_platform_mismatches
        ;;
    4)
        list_discogs_albums
        ;;
    5)
        search_albums
        ;;
    6)
        fix_album_matches
        ;;
    7)
        manually_add_platform_matches
        ;;
    8)
        fix_kink_tsunami_spotify_match
        ;;
    q|Q)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

echo
echo "Done!"
