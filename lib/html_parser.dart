import 'package:html/parser.dart' show parse;

class Track {
  final String trackNumber;
  final String title;
  final String duration;

  Track({
    required this.trackNumber,
    required this.title,
    required this.duration,
  });
}

List<Track> extractTracklist(String html) {
  // Analizar el código HTML
  var document = parse(html);

  // Seleccionar elementos que contienen información de las pistas
  var trackNumberElements = document.querySelectorAll('.track-number-col');
  var titleElements = document.querySelectorAll('.title-col');
  var durationElements = document.querySelectorAll('.time.secondaryText');

  // Lista para almacenar las pistas extraídas
  List<Track> tracks = [];

  // Inicializar contador para el número de pista
  int trackNumberCounter = 1;

  // Iterar sobre los elementos y extraer los datos relevantes
  for (int i = 0; i < trackNumberElements.length; i++) {
    // Convertir el número de pista de texto a número entero
    var trackNumber = int.tryParse(trackNumberElements[i].text.trim()) ?? trackNumberCounter.toString();
    // Incrementar el contador del número de pista
    trackNumberCounter++;

    var title = titleElements[i].text.trim();
    var duration = durationElements[i].text.trim();

    // Crear un objeto Track con los datos extraídos y añadirlo a la lista de pistas
    tracks.add(Track(
      trackNumber: trackNumber.toString(),
      title: title,
      duration: duration,
    ));
  }

  // Devolver la lista de pistas
  return tracks;
}
