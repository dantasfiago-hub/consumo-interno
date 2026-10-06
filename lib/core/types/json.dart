import 'dart:convert';

typedef Json = Map<String, dynamic>;
Json decodeObject(String text) =>
    Map<String, dynamic>.from(jsonDecode(text) as Map);
