import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rateme/core/services/theme_service.dart';
import 'dart:convert';
import '../../database/database_helper.dart';
import 'saved_album_page.dart';
import '../../core/services/user_data.dart';
import '../../core/services/logging.dart';
import '../../ui/widgets/skeleton_loading.dart';

// Define the enum outside the class to make it accessible everywhere
enum SortOrder {
  custom,
  nameAsc,
  nameDesc,
  artistAsc,
  artistDesc,
  ratingDesc,
  ratingAsc,
  dateAdded
}

class SavedRatingsPage extends StatefulWidget {
  const SavedRatingsPage({super.key});

  @override
  State<SavedRatingsPage> createState() => _SavedRatingsPageState();
}

class _SavedRatingsPageState extends State<SavedRatingsPage> {
  // Add these missing key definitions
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  List<Map<String, dynamic>> albums = [];
  List<Map<String, dynamic>> displayedAlbums = []; // For pagination
  List<String> albumOrder = [];
  bool isLoading = true;
  // Add a key for the RefreshIndicator
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // Pagination variables
  int itemsPerPage = 20;
  int currentPage = 0;
  int totalPages = 0;

  // Add sorting options - using the enum defined outside the class
  SortOrder currentSortOrder = SortOrder.custom;

  // Add a new state variable to track when we're in reordering mode
  bool isReorderingMode = false;

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _loadAlbums();
  }

  Future<void> _loadSortPreference() async {
    try {
      final db = DatabaseHelper.instance;
      final savedSortIndex = await db.getSetting('ratings_sort_order');

      if (savedSortIndex != null) {
        int? value = int.tryParse(savedSortIndex.toString());
        if (value != null && value >= 0 && value < SortOrder.values.length) {
          setState(() {
            currentSortOrder = SortOrder.values[value];
            Logging.severe(
                'Loaded saved sort order: $currentSortOrder ($value)');
          });
        }
      }
    } catch (e) {
      Logging.severe('Error loading sort preference: $e');
    }
  }

  Future<void> _loadAlbums() async {
    try {
      // First get all saved albums
      final List<Map<String, dynamic>> savedAlbums =
          await UserData.getSavedAlbums();

      // Log some debug info
      Logging.severe('Loading ${savedAlbums.length} saved albums');

      // Get album order
      List<String> order = await UserData.getAlbumOrder();
      if (order.isEmpty) {
        // If order is empty, create default order from album IDs
        order = savedAlbums.map((album) => album['id'].toString()).toList();
      }

      // Create a new list of albums with added ratings - mutable copy of query results
      final List<Map<String, dynamic>> albumsWithRatings = [];
      int artworkUrlsFound = 0; // Counter for found artwork URLs

      // Calculate ratings for display
      for (var album in savedAlbums) {
        try {
          // Create a mutable copy of the album
          final mutableAlbum = Map<String, dynamic>.from(album);

          // Ensure we have a valid ID
          final albumId = mutableAlbum['id'] ?? mutableAlbum['collectionId'];
          if (albumId == null) continue;

          Logging.severe('Processing album: ${jsonEncode({
                'id': albumId,
                'name': mutableAlbum['name'] ?? mutableAlbum['collectionName']
              })}');

          // Calculate average rating
          Logging.severe('Calculating rating for album ID: $albumId');

          final List<Map<String, dynamic>> ratings =
              await UserData.getSavedAlbumRatings(albumId);

          if (ratings.isNotEmpty) {
            // Only count non-zero ratings
            final nonZeroRatings =
                ratings.where((r) => r['rating'] > 0).toList();
            Logging.severe(
                'Found ${ratings.length} ratings for album $albumId');

            if (nonZeroRatings.isNotEmpty) {
              double sum = 0;
              for (var rating in nonZeroRatings) {
                // Handle different rating types safely
                var ratingValue = rating['rating'];
                if (ratingValue is int) {
                  sum += ratingValue.toDouble();
                } else if (ratingValue is double) {
                  sum += ratingValue;
                } else if (ratingValue != null) {
                  // Last resort - try parsing as double
                  sum += double.tryParse(ratingValue.toString()) ?? 0.0;
                }
              }

              final averageRating = sum / nonZeroRatings.length;

              // Set the rating in our mutable copy
              mutableAlbum['averageRating'] = averageRating;

              Logging.severe(
                  'Album $albumId average rating: $averageRating from ${nonZeroRatings.length} tracks');
            }
          } else {
            Logging.severe('No ratings found for album ID: $albumId');
          }

          // FIXED: Try multiple locations for artwork URL to ensure proper logging
          String artworkUrl = '';
          // First, check artwork_url column
          if (mutableAlbum['artwork_url'] != null &&
              mutableAlbum['artwork_url'].toString().isNotEmpty) {
            artworkUrl = mutableAlbum['artwork_url'].toString();
          }
          // Next, check artworkUrl field
          else if (mutableAlbum['artworkUrl'] != null &&
              mutableAlbum['artworkUrl'].toString().isNotEmpty) {
            artworkUrl = mutableAlbum['artworkUrl'].toString();
          }
          // Finally, check artworkUrl100 field
          else if (mutableAlbum['artworkUrl100'] != null &&
              mutableAlbum['artworkUrl100'].toString().isNotEmpty) {
            artworkUrl = mutableAlbum['artworkUrl100'].toString();
          }
          // Check data field if other methods failed
          else if (mutableAlbum['data'] != null &&
              mutableAlbum['data'].toString().isNotEmpty) {
            try {
              final albumData = jsonDecode(mutableAlbum['data'].toString());
              if (albumData['artworkUrl'] != null) {
                artworkUrl = albumData['artworkUrl'].toString();
              } else if (albumData['artworkUrl100'] != null) {
                artworkUrl = albumData['artworkUrl100'].toString();
              }
            } catch (e) {
              // Ignore JSON parsing errors
            }
          }

          // Log with the comprehensive check result
          Logging.severe(
              'Album artwork URL: ${artworkUrl.isNotEmpty ? artworkUrl : "missing"}');

          // Count found artwork URLs
          if (artworkUrl.isNotEmpty) {
            artworkUrlsFound++;
            // Store the artwork URL in the album for UI use to avoid redundant lookups
            mutableAlbum['_processed_artwork_url'] = artworkUrl;
          }

          // Add to display list
          Logging.severe(
              'Added album to display list: ${mutableAlbum['name'] ?? mutableAlbum['collectionName']}');

          // Add the mutable album to our new list
          albumsWithRatings.add(mutableAlbum);
        } catch (e, stack) {
          Logging.severe('Error processing album', e, stack);
        }
      }

      // Sort albums according to the order
      final Map<String, Map<String, dynamic>> albumMap = {};
      for (var album in albumsWithRatings) {
        final id = album['id']?.toString() ?? album['collectionId']?.toString();
        if (id != null) {
          albumMap[id] = album;
        }
      }

      // Create ordered list
      final orderedAlbums = <Map<String, dynamic>>[];
      for (var id in order) {
        if (albumMap.containsKey(id)) {
          orderedAlbums.add(albumMap[id]!);
        }
      }

      // Add any albums not in the order at the end
      for (var album in albumsWithRatings) {
        final id = album['id']?.toString() ?? album['collectionId']?.toString();
        if (id != null && !order.contains(id)) {
          orderedAlbums.add(album);
          order.add(id);
        }
      }

      Logging.severe('Loaded ${orderedAlbums.length} albums for display');
      Logging.severe(
          'Found $artworkUrlsFound artwork URLs out of ${savedAlbums.length} albums');

      if (mounted) {
        setState(() {
          albums = orderedAlbums;
          albumOrder = order;
          isLoading = false;

          // Calculate pagination
          totalPages = (albums.length / itemsPerPage).ceil();

          // Apply the current sort
          _applySorting();
        });
      }
    } catch (e, stack) {
      Logging.severe('Error loading saved albums', e, stack);
      if (mounted) {
        setState(() {
          albums = [];
          isLoading = false;
        });
      }
    }
  }

  // Add method to sort albums based on the current sort order
  void _applySorting() {
    switch (currentSortOrder) {
      case SortOrder.custom:
        // Use the existing albumOrder
        break;

      case SortOrder.nameAsc:
        albums.sort((a, b) {
          final nameA = a['name'] ?? a['collectionName'] ?? '';
          final nameB = b['name'] ?? b['collectionName'] ?? '';
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        });
        break;

      case SortOrder.nameDesc:
        albums.sort((a, b) {
          final nameA = a['name'] ?? a['collectionName'] ?? '';
          final nameB = b['name'] ?? b['collectionName'] ?? '';
          return nameB.toLowerCase().compareTo(nameA.toLowerCase());
        });
        break;

      case SortOrder.artistAsc:
        albums.sort((a, b) {
          final artistA = a['artist'] ?? a['artistName'] ?? '';
          final artistB = b['artist'] ?? b['artistName'] ?? '';
          return artistA.toLowerCase().compareTo(artistB.toLowerCase());
        });
        break;

      case SortOrder.artistDesc:
        albums.sort((a, b) {
          final artistA = a['artist'] ?? a['artistName'] ?? '';
          final artistB = b['artist'] ?? b['artistName'] ?? '';
          return artistB.toLowerCase().compareTo(artistA.toLowerCase());
        });
        break;

      case SortOrder.ratingDesc:
        albums.sort((a, b) {
          final ratingA = a['averageRating'] ?? 0.0;
          final ratingB = b['averageRating'] ?? 0.0;
          return ratingB.compareTo(ratingA);
        });
        break;

      case SortOrder.ratingAsc:
        albums.sort((a, b) {
          final ratingA = a['averageRating'] ?? 0.0;
          final ratingB = b['averageRating'] ?? 0.0;
          return ratingA.compareTo(ratingB);
        });
        break;

      case SortOrder.dateAdded:
        // If we have a saved timestamp use it, otherwise keep the existing order
        if (albums.isNotEmpty && albums[0].containsKey('savedTimestamp')) {
          albums.sort((a, b) {
            final timeA = a['savedTimestamp'] ?? 0;
            final timeB = b['savedTimestamp'] ?? 0;
            return timeB.compareTo(timeA); // Newest first
          });
        }
        break;
    }

    // Update the displayed albums
    _updateDisplayedAlbums();

    // If it's not custom order, update the album order for saving
    if (currentSortOrder != SortOrder.custom) {
      albumOrder = albums
          .map(
              (a) => a['id']?.toString() ?? a['collectionId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    }
  }

  void _updateDisplayedAlbums() {
    final startIndex = currentPage * itemsPerPage;
    final endIndex = (currentPage + 1) * itemsPerPage;

    setState(() {
      displayedAlbums = albums.sublist(
        startIndex,
        endIndex > albums.length ? albums.length : endIndex,
      );
    });
  }

  void _nextPage() {
    if (currentPage < totalPages - 1) {
      setState(() {
        currentPage++;
        _updateDisplayedAlbums();
      });
    }
  }

  void _previousPage() {
    if (currentPage > 0) {
      setState(() {
        currentPage--;
        _updateDisplayedAlbums();
      });
    }
  }

  void _showSortOptionsMenu(BuildContext context) {
    showMenu<SortOrder>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 50, 0, 0),
      items: [
        _buildPopupMenuItem(SortOrder.custom, 'Custom Order', Icons.sort),
        _buildPopupMenuItem(
            SortOrder.nameAsc, 'Name (A-Z)', Icons.arrow_upward),
        _buildPopupMenuItem(
            SortOrder.nameDesc, 'Name (Z-A)', Icons.arrow_downward),
        _buildPopupMenuItem(SortOrder.artistAsc, 'Artist (A-Z)', Icons.person),
        _buildPopupMenuItem(
            SortOrder.artistDesc, 'Artist (Z-A)', Icons.person_outline),
        _buildPopupMenuItem(
            SortOrder.ratingDesc, 'Rating (High-Low)', Icons.star),
        _buildPopupMenuItem(
            SortOrder.ratingAsc, 'Rating (Low-High)', Icons.star_border),
        _buildPopupMenuItem(
            SortOrder.dateAdded, 'Recently Added', Icons.calendar_today),
        const PopupMenuDivider(),
        PopupMenuItem<SortOrder>(
          value: null, // Special value to indicate reset
          child: Row(
            children: [
              Icon(
                Icons.restore,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Reset to Default Order',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((sortOrder) async {
      if (sortOrder == null) {
        // Reset to default (custom order)
        if (currentSortOrder != SortOrder.custom) {
          setState(() {
            currentSortOrder = SortOrder.custom;
            _applySorting();
          });

          // Save the preference
          final db = DatabaseHelper.instance;
          await db.saveSetting(
              'ratings_sort_order', SortOrder.custom.index.toString());

          // Save the album order
          await UserData.saveAlbumOrder(albumOrder);
        }
        return;
      }

      if (sortOrder != currentSortOrder) {
        setState(() {
          currentSortOrder = sortOrder;
          _applySorting();
        });

        // Save the preference
        final db = DatabaseHelper.instance;
        await db.saveSetting('ratings_sort_order', sortOrder.index.toString());

        // Save the new order if it's a custom order
        if (sortOrder == SortOrder.custom) {
          await UserData.saveAlbumOrder(albumOrder);
        }
      }
    });
  }

  PopupMenuItem<SortOrder> _buildPopupMenuItem(
      SortOrder value, String text, IconData icon) {
    return PopupMenuItem<SortOrder>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            color: currentSortOrder == value
                ? Theme.of(context).colorScheme.primary
                : null,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontWeight: currentSortOrder == value
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: currentSortOrder == value
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          if (currentSortOrder == value)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.check,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  // Add a method to toggle reordering mode
  void _toggleReorderingMode() {
    setState(() {
      isReorderingMode = !isReorderingMode;
      if (!isReorderingMode) {
        // When exiting reorder mode, update the database
        UserData.saveAlbumOrder(albumOrder);
        _showSnackBar('Album order saved');
      } else {
        _showSnackBar('Reordering all ${albums.length} albums');
      }
    });
  }

  // Add a helper method to show snackbar messages
  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Update to use the responsive width factor
    final pageWidth = MediaQuery.of(context).size.width *
        ThemeService.getContentMaxWidthFactor(context);
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    // Get the correct icon color based on theme brightness
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context),
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          automaticallyImplyLeading: false,
          leadingWidth: horizontalPadding + 48,
          title: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text(
              isReorderingMode ? 'Reorder Albums' : 'Saved Albums',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black, // Add explicit color for visibility
              ),
            ),
          ),
          leading: Padding(
            padding: EdgeInsets.only(left: horizontalPadding),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: iconColor),
              padding: const EdgeInsets.all(8.0),
              constraints: const BoxConstraints(),
              iconSize: 24.0,
              splashRadius: 28.0,
              onPressed: () {
                if (isReorderingMode) {
                  _toggleReorderingMode();
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
          actions: [
            // Fix the list type error by correctly handling the conditional rendering
            if (!isReorderingMode)
              if (!isLoading && albums.isNotEmpty)
                Text(
                  _getSortOrderLabel(),
                  style: const TextStyle(fontSize: 14),
                ),
            if (!isReorderingMode)
              IconButton(
                icon: Icon(Icons.sort, color: iconColor),
                tooltip: 'Sort Albums',
                onPressed: () => _showSortOptionsMenu(context),
              ),
            if (!isReorderingMode)
              Padding(
                padding: EdgeInsets.only(right: horizontalPadding),
                child: IconButton(
                  icon: Icon(Icons.reorder, color: iconColor),
                  onPressed: albums.isEmpty ? null : _toggleReorderingMode,
                  tooltip: 'Reorder Albums',
                ),
              )
            else
              Padding(
                padding: EdgeInsets.only(right: horizontalPadding),
                child: TextButton.icon(
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save Order'),
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _toggleReorderingMode,
                ),
              ),
          ],
        ),
        body: Center(
          child: SizedBox(
            width: pageWidth,
            child: isLoading
                ? Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: 10, // Show 10 placeholder items
                          itemBuilder: (context, index) =>
                              const AlbumCardSkeleton(),
                        ),
                      ),
                    ],
                  )
                : albums.isEmpty
                    ? const Center(child: Text('No saved albums'))
                    : RefreshIndicator(
                        key: _refreshIndicatorKey,
                        onRefresh: _refreshData,
                        child: Column(
                          children: [
                            Expanded(
                              // Choose view based on reordering mode - either show all albums
                              // or just the paginated ones
                              child: isReorderingMode
                                  ? _buildReorderableFullListView()
                                  : _buildPaginatedReorderableListView(),
                            ),
                            // Only show pagination controls when not in reordering mode
                            if (totalPages > 1 && !isReorderingMode)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back),
                                      onPressed: currentPage > 0
                                          ? _previousPage
                                          : null,
                                      tooltip: 'Previous page',
                                    ),
                                    Text('${currentPage + 1} / $totalPages'),
                                    IconButton(
                                      icon: const Icon(Icons.arrow_forward),
                                      onPressed: currentPage < totalPages - 1
                                          ? _nextPage
                                          : null,
                                      tooltip: 'Next page',
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  // New method to build the full reorderable list view (no pagination)
  Widget _buildReorderableFullListView() {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false, // Disable default drag handles
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final item = albums.removeAt(oldIndex);
          albums.insert(newIndex, item);

          // Update album order
          albumOrder = albums
              .map((a) =>
                  a['id']?.toString() ?? a['collectionId']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        });
      },
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _buildCompactAlbumCard(album, index);
      },
    );
  }

  // Updated method to handle paginated reorderable list (replaces previous implementation)
  Widget _buildPaginatedReorderableListView() {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) async {
        // Convert display indices to global indices
        final globalOldIndex = currentPage * itemsPerPage + oldIndex;
        final globalNewIndex = currentPage * itemsPerPage +
            (newIndex > oldIndex ? newIndex - 1 : newIndex);

        setState(() {
          final album = albums.removeAt(globalOldIndex);
          albums.insert(globalNewIndex, album);

          // Update album order
          albumOrder = albums
              .map((a) =>
                  a['id']?.toString() ?? a['collectionId']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList();

          _updateDisplayedAlbums();
        });

        await UserData.saveAlbumOrder(albumOrder);
      },
      itemCount: displayedAlbums.length,
      itemBuilder: (context, index) {
        final album = displayedAlbums[index];
        return _buildCompactAlbumCard(album, index);
      },
    );
  }

  // Add this method to handle refresh
  Future<void> _refreshData() async {
    Logging.severe('Refreshing saved albums');

    // Clear cached data
    setState(() {
      albums = [];
      displayedAlbums = [];
      isLoading = true;
    });

    // Reload everything
    await _loadSortPreference();
    await _loadAlbums();

    Logging.severe('Refresh complete, loaded ${albums.length} albums');

    // Show a success message
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Albums refreshed')));
    }
  }

  String _getSortOrderLabel() {
    switch (currentSortOrder) {
      case SortOrder.custom:
        return "Custom";
      case SortOrder.nameAsc:
        return "Name ↑";
      case SortOrder.nameDesc:
        return "Name ↓";
      case SortOrder.artistAsc:
        return "Artist ↑";
      case SortOrder.artistDesc:
        return "Artist ↓";
      case SortOrder.ratingDesc:
        return "Rating ↓";
      case SortOrder.ratingAsc:
        return "Rating ↑";
      case SortOrder.dateAdded:
        return "Recent";
    }
  }

  Widget _buildCompactAlbumCard(Map<String, dynamic> album, int index) {
    // Ensure we handle both formats consistently
    final albumName =
        album['name'] ?? album['collectionName'] ?? 'Unknown Album';
    final artistName =
        album['artist'] ?? album['artistName'] ?? 'Unknown Artist';
    final albumId = album['id'] ?? album['collectionId'] ?? '';

    // Use a simpler approach for getting the rating
    final averageRating = album['averageRating'] ?? 0.0;

    // Extract artwork URL - use the pre-processed version if available to avoid redundant logging
    String artworkUrl = album['_processed_artwork_url'] ?? '';

    // If we don't have a pre-processed URL (fallback), look it up but without logging
    if (artworkUrl.isEmpty) {
      // First try to get from artwork_url column directly
      if (album['artwork_url'] != null &&
          album['artwork_url'].toString().isNotEmpty) {
        artworkUrl = album['artwork_url'].toString();
      }
      // If empty, try extracting from album data
      else {
        try {
          // Try parsing the 'data' field which contains the complete album JSON
          final data = album['data'] as String?;
          if (data != null && data.isNotEmpty) {
            final albumData = jsonDecode(data);
            if (albumData['artworkUrl'] != null) {
              artworkUrl = albumData['artworkUrl'].toString();
            } else if (albumData['artworkUrl100'] != null) {
              artworkUrl = albumData['artworkUrl100']
                  .toString()
                  .replaceAll('100x100', '600x600');
            }
          }
        } catch (e) {
          // Silent error handling - no logging here to avoid duplicates
        }
      }
    }

    // Use a placeholder if no artwork URL is found
    if (artworkUrl.isEmpty) {
      Logging.severe('No artwork URL found for album ${album['id']}');
    }

    return Card(
      key: ValueKey(albumId),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add drag handle at the leftmost position
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
            // Rating display in a prominent box
            Container(
              width: 48, // Rating box width
              height: 48, // Rating box height
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withAlpha(38), // Use withAlpha instead of withOpacity
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  averageRating > 0 ? averageRating.toStringAsFixed(1) : '-',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Album artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: artworkUrl.isNotEmpty
                  ? Image.network(
                      artworkUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 48,
                          height: 48,
                          color: Colors.grey[300],
                          child: const Icon(Icons.album, size: 24),
                        );
                      },
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey[300],
                      child: const Icon(Icons.album, size: 24),
                    ),
            ),
          ],
        ),
        title: Text(
          albumName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          artistName,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyMedium?.color,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: () => _confirmDeleteAlbum(album, index),
          tooltip: 'Delete Album',
        ),
        onTap: () {
          // Create a properly formatted album object before passing to SavedAlbumPage
          final normalizedAlbum = Map<String, dynamic>.from(album);

          // Ensure critical fields exist with proper names
          if (!normalizedAlbum.containsKey('collectionName') &&
              normalizedAlbum.containsKey('name')) {
            normalizedAlbum['collectionName'] = normalizedAlbum['name'];
          }

          if (!normalizedAlbum.containsKey('artistName') &&
              normalizedAlbum.containsKey('artist')) {
            normalizedAlbum['artistName'] = normalizedAlbum['artist'];
          }

          if (!normalizedAlbum.containsKey('artworkUrl100') &&
              normalizedAlbum.containsKey('artworkUrl')) {
            normalizedAlbum['artworkUrl100'] = normalizedAlbum['artworkUrl'];
          }

          _openAlbum(context, albumId);
        },
      ),
    );
  }

  Future<void> _confirmDeleteAlbum(
      Map<String, dynamic> album, int index) async {
    final albumName =
        album['name'] ?? album['collectionName'] ?? 'Unknown Album';
    final artistName =
        album['artist'] ?? album['artistName'] ?? 'Unknown Artist';
    final albumId = album['id'] ?? album['collectionId'] ?? '';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this album?'),
            const SizedBox(height: 16),
            Text(
              albumName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(artistName),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        Logging.severe('Attempting to delete album $albumId: $albumName');
        final success = await UserData.deleteAlbum(album);
        if (success) {
          // Immediately update UI
          setState(() {
            // First remove from displayed albums for immediate feedback
            final displayedIndex = albums.indexOf(displayedAlbums[index]);
            if (displayedIndex >= 0) {
              albums.removeAt(displayedIndex);
            } else {
              // If we can't find in all albums, directly remove from displayed
              displayedAlbums.removeAt(index);
            }

            // Update album order
            albumOrder = albums
                .map((a) =>
                    a['id']?.toString() ?? a['collectionId']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toList();

            // Update pagination if needed
            totalPages = (albums.length / itemsPerPage).ceil();
            if (currentPage >= totalPages && currentPage > 0) {
              currentPage = totalPages - 1;
            }

            // Update displayed albums
            _updateDisplayedAlbums();
          });

          // Save the album order
          await UserData.saveAlbumOrder(albumOrder);

          // Verify album is truly gone from the database with direct check
          final stillExists = await UserData.albumExists(albumId.toString());
          if (stillExists) {
            Logging.severe(
                'WARNING: Album still exists in database after deletion!');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Album may not have been fully deleted. Try refreshing.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Album deleted successfully')),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to delete album'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        Logging.severe('Error deleting album', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting album: $e')),
          );
        }
      }
    }
  }

  void _openAlbum(BuildContext context, String albumId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedAlbumPage(albumId: albumId),
      ),
    );
  }
}
