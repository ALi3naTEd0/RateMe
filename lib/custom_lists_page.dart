import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'user_data.dart';
import 'saved_album_page.dart';
import 'share_widget.dart';
import 'album_model.dart';
import 'logging.dart';
import 'widgets/skeleton_loading.dart';
import 'database/database_helper.dart';
import 'dart:convert';

// Model for custom album lists
class CustomList {
  final String id;
  String name;
  String description;
  List<String> albumIds;
  final DateTime createdAt;
  DateTime updatedAt;

  CustomList({
    required this.id,
    required this.name,
    this.description = '',
    List<String>? albumIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : albumIds = albumIds ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  void cleanupAlbumIds() {
    // Remove nulls, empty strings and invalid IDs
    albumIds.removeWhere((id) => id.isEmpty);
    // Remove duplicates
    albumIds = albumIds.toSet().toList();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'albumIds': albumIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CustomList.fromJson(Map<String, dynamic> json) {
    final list = CustomList(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      albumIds: List<String>.from(json['albumIds'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
    list.cleanupAlbumIds(); // Clean IDs when loading
    return list;
  }
}

// Custom lists management page
class CustomListsPage extends StatefulWidget {
  const CustomListsPage({super.key});

  @override
  State<CustomListsPage> createState() => _CustomListsPageState();
}

class _CustomListsPageState extends State<CustomListsPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  List<CustomList> lists = [];
  List<CustomList> displayedLists = []; // For pagination
  bool isLoading = true;
  bool useDarkButtonText = false;

  // Pagination variables
  int itemsPerPage = 20; // Changed from 15 to 20 to match SavedRatingsPage
  int currentPage = 0;
  int totalPages = 0;

  // Add a key for the RefreshIndicator
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _loadLists();
    _loadButtonPreference();
  }

  Future<void> _loadButtonPreference() async {
    final useDarkText =
        await DatabaseHelper.instance.getSetting('useDarkButtonText') == 'true';
    if (mounted) {
      setState(() {
        useDarkButtonText = useDarkText;
      });
    }
  }

  Future<void> _loadLists() async {
    try {
      setState(() {
        isLoading = true;
      });

      Logging.info('[LISTS] Loading custom lists');

      // Get lists from database
      final dbLists = await DatabaseHelper.instance.getAllCustomLists();

      // Get the saved order
      final orderResult = await DatabaseHelper.instance.getCustomListOrder();

      // Convert to CustomList objects
      final savedLists = dbLists.map((list) => jsonEncode(list)).toList();
      final loadedLists = savedLists
          .map((list) => CustomList.fromJson(jsonDecode(list)))
          .toList();

      // Create a map for sorting
      final listMap = {for (var list in loadedLists) list.id: list};
      final orderedLists = <CustomList>[];

      // First add lists in saved order
      if (orderResult.isNotEmpty) {
        for (final id in orderResult) {
          if (listMap.containsKey(id)) {
            orderedLists.add(listMap[id]!);
            listMap.remove(id);
          }
        }
        // Add any remaining lists
        orderedLists.addAll(listMap.values);
      } else {
        // No saved order, use lists as is
        orderedLists.addAll(loadedLists);
      }

      if (mounted) {
        setState(() {
          lists = orderedLists;
          // Clean all lists when loading
          for (var list in lists) {
            list.cleanupAlbumIds();
          }
          isLoading = false;

          // Calculate pagination
          totalPages = (lists.length / itemsPerPage).ceil();
          _updateDisplayedLists();
        });
      }
    } catch (e, stack) {
      Logging.error('[LISTS] Error loading custom lists', e, stack);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _updateDisplayedLists() {
    final startIndex = currentPage * itemsPerPage;
    final endIndex = (currentPage + 1) * itemsPerPage;

    setState(() {
      displayedLists = lists.sublist(
        startIndex,
        endIndex > lists.length ? lists.length : endIndex,
      );
    });
  }

  void _nextPage() {
    if (currentPage < totalPages - 1) {
      setState(() {
        currentPage++;
        _updateDisplayedLists();
      });
    }
  }

  void _previousPage() {
    if (currentPage > 0) {
      setState(() {
        currentPage--;
        _updateDisplayedLists();
      });
    }
  }

  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _createNewList() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final result = await navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Create New List'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'List Name',
                  hintText: 'e.g. Progressive Rock',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g. My favorite prog rock albums',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => navigator.pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      final newList = CustomList(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameController.text,
        description: descController.text,
      );
      await UserData.saveCustomList(newList);
      _loadLists();
      _showSnackBar('List created successfully');
    }
  }

  Future<void> _editList(CustomList list) async {
    final nameController = TextEditingController(text: list.name);
    final descController = TextEditingController(text: list.description);

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final result = await navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Edit List'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'List Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => navigator.pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      setState(() {
        list.name = nameController.text;
        list.description = descController.text;
        list.updatedAt = DateTime.now();
      });
      await UserData.saveCustomList(list);
      await _loadLists();
      _showSnackBar('List updated successfully');
    }
  }

  Future<void> _deleteList(CustomList list) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final confirm = await navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Delete List'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to delete this list?'),
              const SizedBox(height: 16),
              Text(
                list.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('${list.albumIds.length} albums'),
              if (list.description.isNotEmpty)
                Text(list.description, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              onPressed: () => navigator.pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await UserData.deleteCustomList(list.id);
      _loadLists();
      _showSnackBar('List deleted');
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 1) {
      return 'today';
    } else if (difference.inDays < 2) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else {
      return '${(difference.inDays / 365).floor()} years ago';
    }
  }

  Future<void> _refreshData() async {
    Logging.severe('Refreshing custom lists');

    // Reset the loading state
    setState(() {
      lists = [];
      displayedLists = [];
      isLoading = true;
    });

    // Reload lists
    await _loadLists();

    Logging.severe('Refresh complete, loaded ${lists.length} custom lists');

    // Show a success message
    _showSnackBar('Lists refreshed');
  }

  Future<void> _reorderLists(int oldIndex, int newIndex) async {
    try {
      // Make sure indexes are valid
      if (oldIndex < 0 ||
          oldIndex >= displayedLists.length ||
          newIndex < 0 ||
          newIndex > displayedLists.length) {
        return;
      }

      setState(() {
        // Convert display indices to global indices
        final globalOldIndex = currentPage * itemsPerPage + oldIndex;
        final globalNewIndex = currentPage * itemsPerPage +
            (newIndex > oldIndex ? newIndex - 1 : newIndex);

        // Update the main lists array
        final item = lists.removeAt(globalOldIndex);
        lists.insert(globalNewIndex, item);

        // Update listIds array for database saving
        List<String> listIds = lists
            .map((list) => list.id.toString())
            .where((id) => id.isNotEmpty)
            .toList();

        // Update displayed lists
        _updateDisplayedLists();

        // Save the updated order to database
        DatabaseHelper.instance.saveCustomListOrder(listIds);
      });

      Logging.severe('List reordered and saved to database');
    } catch (e, stack) {
      Logging.severe('Error reordering lists', e, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageWidth = MediaQuery.of(context).size.width * 0.85;
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
          centerTitle: false, // Set to false for left alignment
          automaticallyImplyLeading: false,
          leadingWidth: horizontalPadding + 48,
          title: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text(
              'Custom Lists',
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
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _createNewList,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: useDarkButtonText ? Colors.black : Colors.white,
          child: const Icon(Icons.add),
        ),
        body: Center(
          child: SizedBox(
            width: pageWidth,
            child: isLoading
                ? Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: 8, // Show 8 placeholder items
                          itemBuilder: (context, index) =>
                              const ListCardSkeleton(),
                        ),
                      ),
                    ],
                  )
                : lists.isEmpty
                    ? const Center(child: Text('No custom lists yet'))
                    : RefreshIndicator(
                        key: _refreshIndicatorKey,
                        onRefresh: _refreshData,
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            Expanded(
                              child: ReorderableListView.builder(
                                buildDefaultDragHandles:
                                    false, // Add this line to disable default drag handles
                                onReorder: (oldIndex, newIndex) async {
                                  await _reorderLists(oldIndex, newIndex);
                                },
                                itemCount: displayedLists.length,
                                itemBuilder: (context, index) {
                                  final list = displayedLists[index];
                                  return _buildCompactListCard(list, index);
                                },
                              ),
                            ),
                            // Pagination controls
                            if (totalPages > 1)
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

  Widget _buildCompactListCard(CustomList list, int index) {
    return Card(
      key: ValueKey(list.id),
      margin: const EdgeInsets.symmetric(
          vertical: 2, horizontal: 0), // Reduced from 4 to 2
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 2), // Reduced from 4 to 2
        dense: true, // Added dense property to make it more compact
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Move drag handle to leftmost position
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
            // Replace playlist icon with a better alternative
            Icon(
              Icons
                  .album, // More distinct from drag handle than playlist_play_rounded
              size: 42,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ],
        ),
        title: Text(
          list.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              '${list.albumIds.length} albums',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const Text(' | '),
            Expanded(
              child: Text(
                list.description.isEmpty
                    ? 'Created ${_formatDate(list.createdAt)}'
                    : list.description,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => _editList(list),
              tooltip: 'Edit List',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteList(list),
              tooltip: 'Delete List',
            ),
            // No drag handle icon here - completely removed
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomListDetailsPage(
                initialList: list,
              ),
            ),
          ).then((_) => _loadLists());
        },
      ),
    );
  }
}

// List details page
@immutable
class CustomListDetailsPage extends StatefulWidget {
  final CustomList initialList; // Use final initialList instead of mutable list

  const CustomListDetailsPage({super.key, required this.initialList});

  @override
  State<CustomListDetailsPage> createState() => _CustomListDetailsPageState();
}

class _CustomListDetailsPageState extends State<CustomListDetailsPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  List<Map<String, dynamic>> albums = [];
  bool isLoading = true;

  // Add the mutable state here instead
  late CustomList list; // Create a mutable copy in the state

  @override
  void initState() {
    super.initState();
    // Initialize the mutable state from the widget's immutable property
    list = widget.initialList;
    _loadAlbums();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Calculate average rating for an album
  Future<double> _calculateAlbumRating(dynamic albumId) async {
    try {
      // Handle both string and int albumIds consistently
      final normalizedId = albumId.toString();
      Logging.debug('[RATINGS] Calculating for album ID: $normalizedId');

      // Get ratings from UserData
      final List<Map<String, dynamic>> savedRatings =
          await UserData.getSavedAlbumRatings(normalizedId);

      if (savedRatings.isEmpty) {
        Logging.debug('[RATINGS] No ratings found for album ID: $normalizedId');
        return 0.0;
      }

      Logging.debug(
          '[RATINGS] Found ${savedRatings.length} ratings for album $normalizedId');

      // Filter non-zero ratings
      var validRatings = savedRatings
          .where((r) => r['rating'] != null && (r['rating'] as num) > 0)
          .map((r) => (r['rating'] as num).toDouble())
          .toList();

      if (validRatings.isEmpty) {
        Logging.debug('[RATINGS] No valid ratings for album ID: $normalizedId');
        return 0.0;
      }

      // Calculate average
      double total = validRatings.reduce((a, b) => a + b);
      double average = total / validRatings.length;

      Logging.info(
          '[RATINGS] Album $normalizedId avg: ${average.toStringAsFixed(2)} from ${validRatings.length} tracks');

      return double.parse(average.toStringAsFixed(2));
    } catch (e, stack) {
      Logging.error('[RATINGS] Error calculating album rating', e, stack);
      return 0.0;
    }
  }

  Future<void> _loadAlbums() async {
    List<Map<String, dynamic>> loadedAlbums = [];
    List<String> idsToRemove = [];
    list.cleanupAlbumIds();

    Logging.severe(
        'Loading albums for list: ${list.name} with ${list.albumIds.length} albums');

    for (String albumIdStr in list.albumIds) {
      try {
        // Use our new helper function
        Album? album = await UserData.getAlbumByAnyId(albumIdStr);

        if (album != null) {
          Logging.severe('Found album: ${album.name}');

          // Create a map with all fields normalized - fix to include artwork URL
          final albumMap = {
            'id': album.id,
            'collectionId': album.id,
            'name': album.name,
            'collectionName': album.name,
            'artist': album.artist,
            'artistName': album.artist,
            'artworkUrl': album.artworkUrl,
            'artworkUrl100': album.artworkUrl,
            'platform': album.platform,
            'url': album.url,
            'tracks': album.tracks.map((t) => t.toJson()).toList(),
            'averageRating': await _calculateAlbumRating(album.id),
          };

          // Log to verify artwork URL is included
          Logging.severe('Album has artwork URL: ${album.artworkUrl}');

          loadedAlbums.add(albumMap);
        } else {
          Logging.severe('Album not found, will remove ID: $albumIdStr');
          idsToRemove.add(albumIdStr);
        }
      } catch (e, stack) {
        Logging.severe('Error processing album ID: $albumIdStr', e, stack);
        idsToRemove.add(albumIdStr);
      }
    }

    // Remove invalid IDs after iteration is complete
    if (idsToRemove.isNotEmpty) {
      list.albumIds.removeWhere((id) => idsToRemove.contains(id));
      await UserData.saveCustomList(list);
      Logging.severe(
          'Removed ${idsToRemove.length} invalid album IDs from list');
    }

    Logging.severe('Loaded ${loadedAlbums.length} albums for display in list');

    if (mounted) {
      setState(() {
        albums = loadedAlbums;
        isLoading = false;
      });
    }
  }

  void _openAlbumDetails(int index) {
    final album = albums[index];
    final albumWithDefaults = Map<String, dynamic>.from(album);

    // Ensure all required fields exist
    albumWithDefaults['collectionId'] =
        album['collectionId'] ?? album['id'] ?? 0;
    albumWithDefaults['artistName'] =
        album['artistName'] ?? album['artist'] ?? 'Unknown Artist';
    albumWithDefaults['collectionName'] =
        album['collectionName'] ?? album['name'] ?? 'Unknown Album';
    albumWithDefaults['artworkUrl100'] =
        album['artworkUrl100'] ?? album['artworkUrl'] ?? '';

    final albumId =
        album['id']?.toString() ?? album['collectionId']?.toString();
    if (albumId != null && albumId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SavedAlbumPage(albumId: albumId),
        ),
      ).then((_) {
        // Reload album data when returning from SavedAlbumPage
        _loadAlbums();
      });
    } else {
      // Optionally show an error if albumId is missing
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album ID missing, cannot open album.')),
      );
    }
  }

  void _showShareDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) {
          final shareWidget = ShareWidget(
            key: ShareWidget.shareKey,
            album: albums.first, // Use first album as main album
            tracks: const [], // Empty tracks list for collection view
            ratings: const {}, // Empty ratings for collection view
            averageRating: 0.0, // No average for collection view
            title: list.name, // Add list name as title
            albums: albums, // Add full albums list for collection view
          );

          return AlertDialog(
            content: SingleChildScrollView(child: shareWidget),
            actions: [
              TextButton(
                onPressed: () => navigator.pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final path =
                        await ShareWidget.shareKey.currentState?.saveAsImage();
                    if (mounted && path != null) {
                      navigator.pop();
                      _showSnackBar('Image saved to: $path');
                    }
                  } catch (e) {
                    if (mounted) {
                      navigator.pop();
                      _showSnackBar('Error saving image: $e');
                    }
                  }
                },
                child: const Text('Save Image'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmRemoveAlbum(
      Map<String, dynamic> album, int index) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Album'),
        content: Text(
            'Are you sure you want to remove "${album['name'] ?? album['collectionName'] ?? "this album"}" from this list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        final albumId = album['id'].toString();
        list.albumIds.remove(albumId);
        albums.removeAt(index);
      });

      // Save the updated list
      await saveCustomList(list);

      _showSnackBar('Album removed from list');
    }

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final pageWidth = MediaQuery.of(context).size.width * 0.85;
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
          title: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: iconColor),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(list.name),
                      if (list.description.isNotEmpty)
                        Text(
                          list.description,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: horizontalPadding),
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.settings, color: iconColor),
                onPressed: () => showMenu(
                  context: context,
                  position: const RelativeRect.fromLTRB(100, 50, 0, 0),
                  items: [
                    const PopupMenuItem<String>(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(Icons.file_download),
                          SizedBox(width: 8),
                          Text('Import Data'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.file_upload),
                          SizedBox(width: 8),
                          Text('Export Data'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share),
                          SizedBox(width: 8),
                          Text('Share as Image'),
                        ],
                      ),
                    ),
                  ],
                ).then((value) async {
                  switch (value) {
                    case 'import':
                      final success = await UserData.importData();
                      if (success && mounted) {
                        setState(() => _loadAlbums());
                      }
                      break;
                    case 'export':
                      await UserData.exportData();
                      break;
                    case 'share':
                      _showShareDialog();
                      break;
                  }
                }),
              ),
            ),
            // Delete icon removed from here
          ],
        ),
        body: Center(
          child: SizedBox(
            width: pageWidth,
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : albums.isEmpty
                    ? const Center(child: Text('No albums in this list'))
                    : ReorderableListView.builder(
                        buildDefaultDragHandles:
                            false, // Add this line to prevent automatic drag handles
                        onReorder: (oldIndex, newIndex) async {
                          if (newIndex > oldIndex) newIndex--;
                          setState(() {
                            final album = albums.removeAt(oldIndex);
                            albums.insert(newIndex, album);
                            list.albumIds.clear();
                            list.albumIds.addAll(
                              albums.map((a) => a['collectionId'].toString()),
                            );
                          });
                          await UserData.saveCustomList(list);
                        },
                        itemCount: albums.length,
                        itemBuilder: (context, index) {
                          final album = albums[index];
                          return _buildAlbumCard(album, index);
                        },
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumCard(Map<String, dynamic> album, int index) {
    // Add null safety check for album attributes
    final artistName =
        album['artistName'] ?? album['artist'] ?? 'Unknown Artist';
    final albumName =
        album['collectionName'] ?? album['name'] ?? 'Unknown Album';
    final artworkUrl = album['artworkUrl100'] ?? album['artworkUrl'] ?? '';
    final albumId = album['collectionId'] ?? album['id'] ?? '';
    final rating = album['averageRating'] ?? 0.0;

    return Card(
      key: ValueKey(albumId.toString() + index.toString()),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Move the drag handle to the leftmost position
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
            // Rating display in a prominent box
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: (Theme.of(context).colorScheme.primary.a * 0.15)
                          .toDouble(),
                    ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  rating > 0 ? rating.toStringAsFixed(1) : '-',
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
        // IMPORTANT FIX: Use a simple IconButton here, not a Row which might contain hidden elements
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: () => _confirmRemoveAlbum(album, index),
          tooltip: 'Remove from List',
        ),
        onTap: () => _openAlbumDetails(index),
      ),
    );
  }
}

/// Save a custom list to the database
Future<bool> saveCustomList(CustomList list) async {
  try {
    await UserData.initializeDatabase();

    // Update timestamp
    list.updatedAt = DateTime.now();

    // Check database schema to determine available columns
    final db = await UserData.getDatabaseInstance();
    final tableInfo = await db.rawQuery("PRAGMA table_info(custom_lists)");

    // Log table schema for debugging
    Logging.severe(
        'Custom lists table schema: ${tableInfo.map((row) => row['name']).toList()}');

    // Check if createdAt and updatedAt columns exist
    final hasCreatedAt = tableInfo.any((col) => col['name'] == 'createdAt');
    final hasUpdatedAt = tableInfo.any((col) => col['name'] == 'updatedAt');

    // Build insert data based on available columns
    final Map<String, dynamic> insertData = {
      'id': list.id,
      'name': list.name,
      'description': list.description,
    };

    // Only add timestamp fields if they exist in the schema
    if (hasCreatedAt) {
      insertData['createdAt'] = list.createdAt.toIso8601String();
    }

    if (hasUpdatedAt) {
      insertData['updatedAt'] = list.updatedAt.toIso8601String();
    }

    // Log the data we're about to insert
    Logging.severe('Inserting custom list with data: $insertData');

    // Save list to database using modified data
    await UserData.saveCustomList(list);

    // Clear existing album relationships
    await db.delete(
      'album_lists',
      where: 'list_id = ?',
      whereArgs: [list.id],
    );

    // Add album-list relationships
    for (int i = 0; i < list.albumIds.length; i++) {
      String albumId = list.albumIds[i];
      Logging.severe('Adding album $albumId to list ${list.id}');
      await db.insert(
        'album_lists',
        {
          'list_id': list.id,
          'album_id': albumId,
          'position': i,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    Logging.severe(
        'Custom list saved: ${list.name} with ${list.albumIds.length} albums');
    return true;
  } catch (e, stack) {
    Logging.severe('Error saving custom list', e, stack);
    return false;
  }
}

// Add method to fetch lists from database
Future<List<CustomList>> getCustomListsFromDatabase() async {
  try {
    final dbHelper = DatabaseHelper.instance;
    final listsData = await dbHelper.getAllCustomLists();

    if (listsData.isEmpty) {
      Logging.severe('No custom lists found in database');
      return [];
    }

    final lists = listsData.map((data) {
      return CustomList.fromJson(data);
    }).toList();

    Logging.severe('Loaded ${lists.length} custom lists from database');
    return lists;
  } catch (e, stack) {
    Logging.severe('Error loading custom lists from database', e, stack);
    return [];
  }
}

// Add method to delete list from database
Future<bool> deleteCustomListFromDatabase(String listId) async {
  try {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.deleteCustomList(listId);

    Logging.severe('Deleted custom list from database: $listId');
    return true;
  } catch (e, stack) {
    Logging.severe('Error deleting custom list from database', e, stack);
    return false;
  }
}

// Add method to get albums from a list directly from database
Future<List<Map<String, dynamic>>> getListAlbumsFromDatabase(
    String listId) async {
  try {
    final dbHelper = DatabaseHelper.instance;
    final albumsData = await dbHelper.getAlbumsInList(listId);

    if (albumsData.isEmpty) {
      Logging.severe('No albums found in list $listId');
      return [];
    }

    Logging.severe('Loaded ${albumsData.length} albums for list $listId');
    return albumsData;
  } catch (e, stack) {
    Logging.severe('Error loading albums for list from database', e, stack);
    return [];
  }
}

// Add extension method to help with color values
extension ColorWithValues on Color {
  Color withValues({double? alpha}) {
    return Color.fromARGB(
      alpha != null ? (alpha * 255).round() : a.round(),
      r.round(),
      g.round(),
      b.round(),
    );
  }
}

// Extension to DatabaseHelper to handle list order
extension CustomListOrderExtension on DatabaseHelper {
  Future<void> saveCustomListOrder(List<String> listIds) async {
    final db = await database;

    try {
      // First check if the list_order table exists
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='list_order'");

      if (tableCheck.isEmpty) {
        // Create the table if it doesn't exist
        Logging.severe('Creating list_order table since it does not exist');
        await db.execute('''
          CREATE TABLE list_order (
            list_id TEXT PRIMARY KEY,
            position INTEGER
          )
        ''');
      }

      // Use a transaction for better reliability
      await db.transaction((txn) async {
        // Clear existing order
        await txn.delete('list_order');

        // Insert new order
        for (int i = 0; i < listIds.length; i++) {
          await txn.insert('list_order', {
            'list_id': listIds[i],
            'position': i,
          });
        }
      });

      Logging.severe('Saved order for ${listIds.length} lists');
    } catch (e, stack) {
      Logging.severe('Error saving list order', e, stack);
    }
  }

  Future<List<String>> getCustomListOrder() async {
    try {
      final db = await database;

      // Check if the table exists first
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='list_order'");

      if (tableCheck.isEmpty) {
        // Table doesn't exist yet, return empty list
        return [];
      }

      // Get ordered list IDs
      final results = await db.query(
        'list_order',
        orderBy: 'position ASC',
      );

      return results.map((row) => row['list_id'].toString()).toList();
    } catch (e, stack) {
      Logging.severe('Error getting custom list order', e, stack);
      return [];
    }
  }
}

// Add loadCustomLists method to UserData class that respects order
extension CustomListsUserDataExtension on UserData {
  static Future<List<CustomList>> getOrderedCustomLists() async {
    try {
      final db = DatabaseHelper.instance;

      // Get all lists first
      // Fix: Qualify the static method with UserData class name
      final lists = await UserData.getCustomLists();

      // Get saved order
      final orderResult = await db.getCustomListOrder();

      // If we have order data, use it to sort the lists
      if (orderResult.isNotEmpty) {
        // Create a map for faster lookups
        final listMap = {for (var list in lists) list.id: list};

        // Create ordered list
        final orderedLists = <CustomList>[];

        // First add lists in the saved order
        for (final id in orderResult) {
          if (listMap.containsKey(id)) {
            orderedLists.add(listMap[id]!);
            listMap.remove(id); // Remove to track what's been added
          }
        }

        // Add any remaining lists (not in saved order) at the end
        orderedLists.addAll(listMap.values);

        return orderedLists;
      }

      // If no order data, return the original list
      return lists;
    } catch (e, stack) {
      Logging.severe('Error getting ordered custom lists', e, stack);
      return [];
    }
  }
}
