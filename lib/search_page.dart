import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'album_details_page.dart'; // Importa la página de detalles del álbum

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Search Albums or Paste URL',
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () {
                    _searchOrLoadFromURL(searchController.text);
                  },
                ),
              ),
              onChanged: _onSearchChanged,
              maxLength: 255, // Máximo de caracteres para la entrada de búsqueda
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: searchResults.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: Image.network(
                  searchResults[index]['artworkUrl100'],
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.album),
                ),
                title: Text(searchResults[index]['collectionName']),
                subtitle: Text(searchResults[index]['artistName']),
                onTap: () =>
                    _showAlbumDetails(searchResults[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onSearchChanged(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    final url = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() => searchResults = data['results']);
  }

  void _searchOrLoadFromURL(String input) async {
    if (input.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    // Verificar si la entrada es una URL válida de iTunes
    final Uri? parsedUrl = Uri.tryParse(input); // Usar Uri? en lugar de Uri
    if (parsedUrl != null &&
        parsedUrl.scheme == 'http' &&
        parsedUrl.host.contains('itunes.apple.com')) {
      // La entrada es una URL de iTunes
      // Realizar lógica para cargar datos desde la URL
      // Por ahora, simplemente imprimir la URL
      print('URL ingresada: $input');
      return;
    }

    // La entrada no es una URL, realizar búsqueda normal
    final url = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(input)}&entity=album');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() => searchResults = data['results']);
  }

  void _showAlbumDetails(dynamic album) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => AlbumDetailsPage(album: album)));
  }
}
