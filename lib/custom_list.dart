import 'dart:convert';

class CustomList {
  String name;
  List<Map<String, dynamic>> albums;

  CustomList({required this.name, required this.albums});

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'albums': albums,
    };
  }

  factory CustomList.fromJson(Map<String, dynamic> json) {
    return CustomList(
      name: json['name'],
      albums: List<Map<String, dynamic>>.from(json['albums']),
    );
  }
}
