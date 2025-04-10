# RateMe Application Architecture

This diagram shows the full architecture and data flow of the RateMe application, including all modules and their relationships.

## Interactive Diagram (for GitHub and Mermaid-compatible tools)

```mermaid
flowchart TB
    %% Main Application Entry
    main["main.dart<br/>App Entry Point"]
    
    %% Core Modules
    user_data["user_data.dart<br/>Data Management"]
    album_model["album_model.dart<br/>Data Models"]
    search_service["search_service.dart<br/>Search APIs"]
    platform_service["platform_service.dart<br/>Platform Integration"]
    
    %% Database Components
    subgraph Database["Database Layer"]
        db_helper["database_helper.dart<br/>SQLite Operations"]
        migration_utility["migration_utility.dart<br/>Data Migration"]
        migration_progress["migration_progress_page.dart<br/>Migration UI"]
    end
    
    %% UI Components
    subgraph UI["UI Components"]
        music_home["MusicRatingHomePage<br/>Main UI"]
        details_page["details_page.dart<br/>Album Details"]
        saved_ratings["saved_ratings_page.dart<br/>Saved Albums"]
        saved_album["saved_album_page.dart<br/>Single Album View"]
        custom_lists["custom_lists_page.dart<br/>Lists Management"]
        settings["settings_page.dart<br/>App Settings"]
        share_widget["share_widget.dart<br/>Image Sharing"]
    end
    
    %% Utility Components
    subgraph Utilities["Utility Modules"]
        logging["logging.dart<br/>Logging System"]
        api_keys["api_keys.dart<br/>API Credentials"]
        debug_util["debug_util.dart<br/>Debugging Tools"]
        theme["theme.dart<br/>App Theming"]
        migration_util["migration_util.dart<br/>Legacy Migration"]
        platform_ui["platform_ui.dart<br/>UI Components"]
    end
    
    %% Widgets and UI Components
    subgraph Widgets["Widget Components"]
        skeleton_loading["skeleton_loading.dart<br/>Loading Placeholders"]
        platform_match["platform_match_widget.dart<br/>Platform Links"]
        footer["footer.dart<br/>App Footer"]
    end
    
    %% Data Flow
    main --> music_home
    main --> user_data
    main --> logging
    
    %% Database interactions
    user_data <--> Database
    db_helper --> migration_utility
    migration_utility --> migration_progress
    
    %% UI Flow
    music_home --> details_page
    music_home --> saved_ratings
    music_home --> custom_lists
    music_home --> settings
    
    saved_ratings --> saved_album
    saved_album --> details_page
    custom_lists --> saved_album
    
    %% Service Interactions
    details_page --> user_data
    details_page --> search_service
    details_page --> platform_match
    details_page --> share_widget
    
    search_service --> api_keys
    search_service --> platform_service
    
    %% Utility Usage
    user_data --> migration_util
    user_data --> album_model
    album_model --> migration_util
    
    skeleton_loading --> details_page
    skeleton_loading --> saved_ratings
    skeleton_loading --> custom_lists
    
    platform_match --> search_service
    
    %% Theme and UI Components
    theme --> main
    platform_ui --> music_home
    platform_ui --> saved_ratings
    
    %% Logging
    logging --> main
    logging --> user_data
    logging --> search_service
    logging --> details_page
    
    %% Debug Utilities
    debug_util --> settings
    
    %% Footer Widget
    footer --> music_home
    footer --> saved_ratings
    
    %% Style definitions
    classDef core fill:#f9f,stroke:#333,stroke-width:2px;
    classDef db fill:#bbf,stroke:#333,stroke-width:2px;
    classDef ui fill:#bfb,stroke:#333,stroke-width:2px;
    classDef utility fill:#fbb,stroke:#333,stroke-width:2px;
    classDef widget fill:#ffb,stroke:#333,stroke-width:2px;
    
    %% Apply styles
    class main,user_data,album_model,search_service,platform_service core;
    class db_helper,migration_utility,migration_progress db;
    class music_home,details_page,saved_ratings,saved_album,custom_lists,settings,share_widget ui;
    class logging,api_keys,debug_util,theme,migration_util,platform_ui utility;
    class skeleton_loading,platform_match,footer widget;

    %% Add legends
    subgraph Legend
        core_legend["Core Modules"]
        db_legend["Database Components"]
        ui_legend["UI Components"]
        utility_legend["Utility Modules"]
        widget_legend["Widget Components"]
    end
    
    %% Apply legend styles
    class core_legend core;
    class db_legend db;
    class ui_legend ui;
    class utility_legend utility;
    class widget_legend widget;
```

## Static Image (for Obsidian and other non-Mermaid compatible tools)

For tools that don't support Mermaid rendering, you can view the diagram as a static image:

![RateMe Architecture Diagram](/assets/images/architecture_diagram.svg)

You can also access the diagram directly from MermaidChart:
[View on MermaidChart](https://www.mermaidchart.com/raw/979de47a-08ba-4f1a-b31f-3469cf6a303f?theme=light&version=v0.1&format=svg)

## Module Descriptions

### Core Modules
- **main.dart**: Application entry point and initialization
- **user_data.dart**: Central data management and persistence
- **album_model.dart**: Data models for albums and tracks
- **search_service.dart**: Music platform search APIs integration
- **platform_service.dart**: Platform-specific service integration

### Database Layer
- **database_helper.dart**: SQLite database operations
- **migration_utility.dart**: SharedPreferences to SQLite migration
- **migration_progress_page.dart**: Migration UI and progress tracking

### UI Components
- **MusicRatingHomePage**: Main app UI and search interface
- **details_page.dart**: Album details and rating interface
- **saved_ratings_page.dart**: User's saved albums collection
- **saved_album_page.dart**: Single album view from saved collection
- **custom_lists_page.dart**: Custom album lists management
- **settings_page.dart**: App settings and preferences
- **share_widget.dart**: Image generation for sharing

### Utility Modules
- **logging.dart**: Application logging system
- **api_keys.dart**: API credentials management
- **debug_util.dart**: Debugging and diagnostic tools
- **theme.dart**: App theming and styles
- **migration_util.dart**: Legacy data migration utilities
- **platform_ui.dart**: Platform-specific UI components

### Widget Components
- **skeleton_loading.dart**: Loading placeholder animations
- **platform_match_widget.dart**: Music platform linking
- **footer.dart**: App footer with version info


                                  RateMe - User Journey Linear Flow
┌───────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                       │
│  ┌─────────┐        ┌─────────┐        ┌─────────────┐        ┌───────────────┐        ┌─────────┐    │
│  │         │        │         │        │             │        │               │        │         │    │
│  │  Start  ├───────►│  Search ├───────►│ Album List  ├───────►│ Album Details ├───────►│  Rate   │    │
│  │         │        │         │        │             │        │               │        │         │    │
│  └─────────┘        └─────┬───┘        └──────┬──────┘        └───────┬───────┘        └─────┬───┘    │
│                           │                   │                       │                      │        │
│                           ▼                   ▼                       ▼                      ▼        │
│                    ┌─────────────┐     ┌─────────────┐         ┌──────────────┐      ┌─────────────┐  │
│                    │ Platform    │     │ Search      │         │ Match on     │      │ Store       │  │
│                    │ Selection   │     │ Service     │         │ External     │      │ in SQLite   │  │
│                    └─────────────┘     └─────────────┘         │ Platforms    │      └─────────────┘  │
│                                                                └──────────────┘            │          │
│                                                                                            ▼          │
│  ┌────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│  │            │     │             │     │             │     │             │     │             │       │
│  │ Share      │◄────┤ View        │◄────┤ Custom      │◄────┤ Saved       │◄────┤ Export      │       │
│  │ as Image   │     │ List        │     │ Lists       │     │ Albums      │     │ Backup      │       │
│  │            │     │             │     │             │     │             │     │             │       │
│  └────────────┘     └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘       │
│                                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘


                               Key Components and Data Flow
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                        │
│  ┌─────────────┐        ┌─────────────┐        ┌─────────────┐        ┌─────────────┐  │
│  │             │        │             │        │             │        │             │  │
│  │  User       ├────1───► Search      ├────2───► Album       ├────3───► Rating      │  │
│  │  Interface  │        │ Service     │        │ Details     │        │ System      │  │
│  │             │◄───8───┤             │◄───7───┤             │◄───4───┤             │  │
│  └─────────────┘        └─────────────┘        └─────────────┘        └─────────────┘  │
│         │                      │                      │                      │         │
│         │                      │                      │                      │         │
│         9                      │                      │                      5         │
│         │                      │                      │                      │         │
│         ▼                      │                      │                      ▼         │
│  ┌─────────────┐               │                      │               ┌─────────────┐  │
│  │             │               │                      │               │             │  │
│  │  Custom     │               │                      │               │  Database   │  │
│  │  Lists      │◄──────────────┴──────────────────────┴──────────────►│  (SQLite)   │  │
│  │             │                         6                            │             │  │
│  └─────────────┘                                                      └─────────────┘  │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘

Data Flow Steps:
1. User searches for an album on a selected platform (iTunes, Spotify, or Deezer)
2. Search results are returned and displayed in the album list
3. User selects an album to view details and rate tracks
4. User rates tracks and the data is processed by the rating system
5. Ratings are saved to the SQLite database
6. All data (albums, ratings, lists) is persisted in the database
7. Album details can be refreshed or updated
8. User returns to main interface
9. User can organize albums into custom lists for better management
