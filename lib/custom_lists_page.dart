import 'package:flutter/material.dart';
import 'user_data.dart';
import 'saved_album_page.dart';
import 'share_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

// Model for custom album lists
class CustomList {
  final String id;
  String name;  // Removed final to allow modification
  String description;
  List<String> albumIds;  // Removed final to allow modification
  final DateTime createdAt;
  DateTime updatedAt;

  CustomList({
    required this.id,
    required this.name,
    this.description = '',
    List<String>? albumIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : 
    albumIds = albumIds ?? [],
    createdAt = createdAt ?? DateTime.now(),
    updatedAt = updatedAt ?? DateTime.now();

  void cleanupAlbumIds() {
    // Remove nulls, empty strings and invalid IDs
    albumIds.removeWhere((id) => 
      id == null || 
      id.isEmpty || 
      int.tryParse(id) == null
    );
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
      description: json['description'],
      albumIds: List<String>.from(json['albumIds']),
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
  List<CustomList> lists = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    final loadedLists = await UserData.getCustomLists();
    if (mounted) {
      setState(() {
        lists = loadedLists;
        // Clean all lists when loading
        for (var list in lists) {
          list.cleanupAlbumIds();
        }
        isLoading = false;
      });
    }
  }

  Future<void> _createNewList() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
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
    }
  }

  Future<void> _editList(CustomList list) async {
    final nameController = TextEditingController(text: list.name);
    final descController = TextEditingController(text: list.description);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      setState(() {
        list.name = nameController.text; // Update list name
        list.description = descController.text;
        list.updatedAt = DateTime.now();
      });
      await UserData.saveCustomList(list);
      await _loadLists(); // Ensure list is reloaded
    }
  }

  Future<void> _deleteList(CustomList list) async {
    // Add confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await UserData.deleteCustomList(list.id);
      _loadLists();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Lists')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewList,
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : lists.isEmpty
              ? const Center(child: Text('No custom lists yet'))
              : ReorderableListView.builder(
                  onReorder: (oldIndex, newIndex) async {  // Added async
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      final item = lists.removeAt(oldIndex);
                      lists.insert(newIndex, item);
                    });
                    // Save the new order
                    for (var list in lists) {
                      await UserData.saveCustomList(list);
                    }
                  },
                  itemCount: lists.length,
                  itemBuilder: (context, index) {
                    final list = lists[index];
                    return ListTile(
                      key: Key(list.id),
                      leading: const Icon(Icons.playlist_play),
                      title: Text(list.name),
                      subtitle: Text(
                        list.description.isEmpty
                            ? '${list.albumIds.length} albums'
                            : list.description,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(list.albumIds.length.toString()),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editList(list),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteList(list),
                          ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CustomListDetailsPage(list: list),
                        ),
                      ).then((_) => _loadLists()),
                    );
                  },
                ),
    );
  }
}

// List details page
class CustomListDetailsPage extends StatefulWidget {
  final CustomList list;

  const CustomListDetailsPage({
    super.key,
    required this.list,
  });

  @override
  State<CustomListDetailsPage> createState() => _CustomListDetailsPageState();
}

class _CustomListDetailsPageState extends State<CustomListDetailsPage> {
  List<Map<String, dynamic>> albums = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    List<Map<String, dynamic>> loadedAlbums = [];
    widget.list.cleanupAlbumIds(); // Clean list before loading
    for (String albumId in widget.list.albumIds) {
      final album = await UserData.getSavedAlbumById(int.parse(albumId));
      if (album != null) {
        final ratings = await UserData.getSavedAlbumRatings(int.parse(albumId));
        double averageRating = 0.0;
        if (ratings.isNotEmpty) {
          final total = ratings.fold(0.0, (sum, rating) => sum + rating['rating']);
          averageRating = total / ratings.length;
        }
        album['averageRating'] = averageRating;
        loadedAlbums.add(album);
      } else {
        // Remove invalid album ID
        widget.list.albumIds.remove(albumId);
        await UserData.saveCustomList(widget.list);
      }
    }
    if (mounted) {
      setState(() {
        albums = loadedAlbums;
        isLoading = false;
      });
    }
  }

  void _removeAlbum(int index) async {
    // Add confirmation dialog
    final album = albums[index];
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Album'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to remove this album from the list?'),
            const SizedBox(height: 16),
            Text(
              album['artistName'] ?? 'Unknown Artist',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(album['collectionName'] ?? 'Unknown Album'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    // Only remove if confirmed
    if (result == true) {
      final albumId = album['collectionId'].toString();
      setState(() {
        widget.list.albumIds.remove(albumId);
        albums.removeAt(index);
      });
      await UserData.saveCustomList(widget.list);
    }
  }

  void _openAlbumDetails(int index) {
    final album = albums[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedAlbumPage(
          album: album,
          isBandcamp: album['url']?.toString().contains('bandcamp.com') ?? false,
        ),
      ),
    ).then((_) => _loadAlbums());
  }

  void _handleImageShare(String imagePath) async {
    try {
      await Share.shareXFiles([XFile(imagePath)]);  // Reemplazar ShareExtend.share
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }

  void _showShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final shareWidget = ShareWidget(
          key: ShareWidget.shareKey,
          title: widget.list.name,
          albums: albums,
        );
        return AlertDialog(
          content: SingleChildScrollView(child: shareWidget),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final path = await ShareWidget.shareKey.currentState?.saveAsImage();
                  if (mounted && path != null) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Image saved to: $path')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving image: $e')),
                    );
                  }
                }
              },
              child: const Text('Save Image'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.list.name),
            if (widget.list.description.isNotEmpty)
              Text(
                widget.list.description,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) async {
              switch (value) {
                case 'import':
                  final success = await UserData.importData(context);
                  if (success && mounted) {
                    setState(() => _loadAlbums());
                  }
                  break;
                case 'export':
                  await UserData.exportData(context);
                  break;
                case 'share':
                  _showShareDialog(context);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
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
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : albums.isEmpty
              ? const Center(child: Text('No albums in this list'))
              : ReorderableListView.builder(
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      final album = albums.removeAt(oldIndex);
                      albums.insert(newIndex, album);
                      widget.list.albumIds.clear();
                      widget.list.albumIds.addAll(
                        albums.map((a) => a['collectionId'].toString()),
                      );
                    });
                    await UserData.saveCustomList(widget.list);
                  },
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return ListTile(
                      key: ValueKey(album['collectionId']),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: isDarkTheme ? Colors.white : Colors.black),
                            ),
                            child: Center(
                              child: Text(
                                album['averageRating']?.toStringAsFixed(2) ?? 'N/A',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkTheme ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Image.network(
                            album['artworkUrl100'],
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.album),
                          ),
                        ],
                      ),
                      title: Text(album['collectionName'] ?? 'N/A'),
                      subtitle: Text(album['artistName'] ?? 'N/A'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _removeAlbum(index),
                          ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                      onTap: () => _openAlbumDetails(index),
                    );
                  },
                ),
    );
  }
}
