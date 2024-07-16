import 'dart:async';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:remove_diacritic/remove_diacritic.dart';
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FlutterTts _flutterTts = FlutterTts();
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _text = "...";
  List<Contact> _contacts = [];
  List<Map> _voces = [];
  Map? _vozActual;
  List<String> _conversation = [];
  Timer? _listeningTimer;

  @override
  void initState() {
    super.initState();
    initTTS();
    _requestPermissions();

    // Agregar frase de bienvenida al iniciar la aplicación
    _flutterTts.speak("Bienvenido a AidVoice, tu asistente de voz. ¿En qué puedo ayudarte?");
    
    // Mostrar instrucciones al inicio
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showInstructions();
    });

    // Iniciar escucha continua
    _startListening();
  }

  @override
  void dispose() {
    _listeningTimer?.cancel();
    super.dispose();
  }

  void initTTS() {
    _flutterTts.setProgressHandler((text, start, end, word) {
      setState(() {
        _text = text;
      });
    });
    _flutterTts.getVoices.then((data) {
      try {
        List<Map> voces = List<Map>.from(data);
        setState(() {
          _voces = voces
              .where((voz) => voz["locale"].startsWith("es"))
              .map((voz) => {
                    "name": voz["name"],
                    "locale": voz["locale"],
                    "gender": voz["name"].toLowerCase().contains("female")
                        ? "Femenino"
                        : "Masculino"
                  })
              .toList();
          _vozActual = _voces.first;
          setVoz(_vozActual!);
        });
      } catch (e) {
        print(e);
      }
    });
  }

  void setVoz(Map voz) {
    _flutterTts.setVoice({"name": voz["name"], "locale": voz["locale"]});
  }

  // Future<void> _requestPermissions() async {
  //   await Permission.contacts.request();
  //   await Permission.phone.request();
  //   if (await Permission.contacts.isGranted) {
  //     _loadContacts();
  //   } else {
  //     _flutterTts.speak("Permiso de contactos no concedido");
  //   }
  // }
  
  Future<void> _requestPermissions() async {
    // Solicitar permisos necesarios
    await _requestAllPermissions();
    
    // Cargar contactos si se concedió el permiso
    if (await Permission.contacts.isGranted) {
      _loadContacts();
    } else {
      _flutterTts.speak("Permiso de contactos no concedido");
    }
  }

  Future<void> _requestAllPermissions() async {
    // Solicitar todos los permisos necesarios
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.contacts,
      Permission.camera,
      Permission.phone,
      Permission.calendar,
      Permission.storage,
      //permiso segundo plano
      Permission.location,
      //permiso de sms
      Permission.sms,
      //permiso de superposición
      Permission.accessMediaLocation,
      //permiso record audio
      Permission.manageExternalStorage,
      //permiso galeria
      Permission.photos,
    ].request();

    // Verificar si todos los permisos fueron concedidos
    bool allGranted = statuses.values.every((status) => status.isGranted);
    if (!allGranted) {
      // Manejar el caso donde no se concedieron todos los permisos
      _flutterTts.speak("No se concedieron todos los permisos necesarios.");
    }
  }


  Future<void> _loadContacts() async {
    List<Contact> contacts = (await ContactsService.getContacts()).toList();
    setState(() {
      _contacts = contacts;
    });
  }

  void _startListening() {
    _listeningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isListening) {
        _listen();
      }
    });
  }

  void _listen() async {
  if (!_isListening) {
    bool available = await _speech.initialize(
      onStatus: (val) {
        setState(() {
          _isListening = _speech.isListening;
        });
      },
      onError: (val) {
        print("onError: ${val.errorMsg}, permanent: ${val.permanent}");
        setState(() {
          _isListening = false;
        });
      },
    );
    if (available) {
      setState(() {
        _isListening = true;
      });
      _speech.listen(
        onResult: (val) {
          setState(() {
            _text = val.recognizedWords;
          });
          print("Recognized: ${val.recognizedWords}");
          if (val.finalResult) {
            _respondToUser(_text); // Respond to user speech only once
            setState(() {
              _isListening = false; // Stop listening after response
            });
          }
        },
      );
    }
  } else {
    setState(() {
      _isListening = false;
    });
    _speech.stop();
  }
}



  void _respondToUser(String userText) {
    // Check if userText is not empty or just whitespace
    if (userText.trim().isEmpty) {
      return;
    }

    _conversation.add("Tú: $userText");

    Map<String, Function> commands = {
      "abrir facebook": () => _launchURL("https://www.facebook.com"),
      "abrir instagram": () => _launchURL("https://www.instagram.com"),
      "abrir snapchat": () => _launchURL("https://www.snapchat.com"),
      "reproducir musica": () => _askMusicService(),
      "abrir youtube": () => _launchURL("https://www.youtube.com"),
      "abrir calendario": () => _openCalendar(),
      "abrir camara": () => _openCamera(), // Nueva función para abrir la cámara
      "hola": () => _flutterTts.speak("¡Hola! ¿Cómo estás?"),
      "cómo estas": () => _flutterTts.speak("Estoy bien, gracias por preguntar. ¿Y tú?"),
      "bien y tu": () => _flutterTts.speak("Estoy super, me alegro que estés bien"),
      "que haces": () => _flutterTts.speak("Estoy aquí para ayudarte. ¿En qué puedo asistirte?"),
      "adios": () => _flutterTts.speak("Adiós, ¡que tengas un buen día!"),
      "cual es tu nombre": () => _flutterTts.speak("Soy AidVoice, tu asistente virtual. Un gusto en ayudarte."),
      "que dia es hoy": () => _flutterTts.speak("Hoy es ${_getFormattedDate()}"),
      "qué hora es": () => _flutterTts.speak("Son las ${_getCurrentTime()}"),
    };

    String normalizedText = removeDiacritics(userText.toLowerCase());

    // Check for commands
    bool commandRecognized = false;
    commands.forEach((command, function) {
      if (normalizedText.contains(command)) {
        function(); // Execute the function directly
        commandRecognized = true;
      }
    });

    // Handle specific contact-related commands
    if (normalizedText.startsWith("llamar a ")) {
      _callContact(normalizedText.substring(8).trim().toLowerCase());
      commandRecognized = true;
    }

    if (normalizedText.startsWith("enviar mensaje a ")) {
      _sendMessageToContact(normalizedText.substring(17).trim().toLowerCase());
      commandRecognized = true;
    }

    // Default response for unrecognized commands
    if (!commandRecognized) {
      _flutterTts.speak("Lo siento, no entendí eso. ¿Puedes repetirlo?");
    }

    // Add assistant response to conversation (excluding commands that trigger actions)
    if (!commands.containsKey(normalizedText) && !normalizedText.startsWith("llamar a ") && !normalizedText.startsWith("enviar mensaje a ")) {
      setState(() {
        _conversation.add("Asistente: ${commandRecognized ? 'Comando ejecutado' : 'Lo siento, no entendí eso. ¿Puedes repetirlo?'}");
      });
    }
  }

  void _askMusicService() {
    _flutterTts.speak("¿Deseas reproducir música en YouTube?");

    try {
      _speech.listen(
        onResult: (val) {
          if (val.finalResult) {
            String response = val.recognizedWords.toLowerCase();
            if (response.contains("si") || response.contains("sí")) {
              _launchURL("https://www.youtube.com");
            } else {
              _flutterTts.speak("Entiendo, no reproduciré música ahora.");
            }
          }
        },
      );
    } catch (e) {
      print("Error al escuchar la respuesta del usuario: $e");
    }
  }

  void _openCalendar() async {
    try {
      await _launchURL("content://com.android.calendar/time/");
    } catch (e) {
      _flutterTts.speak("No se puede abrir el calendario.");
    }
  }

  void _callContact(String contactName) {
    Contact? contact = _findContactByName(contactName);

    if (contact != null && contact.phones!.isNotEmpty) {
      _makePhoneCall(contact.phones!.first.value!, contact.displayName!);
    } else {
      _flutterTts.speak("No se encontró el contacto $contactName en la lista o no tiene número de teléfono.");
    }
  }

  Contact? _findContactByName(String nameToFind) {
    Contact? foundContact;

    _contacts.forEach((contact) {
      String normalizedDisplayName = removeDiacritics(contact.displayName!.toLowerCase());
      if (normalizedDisplayName.contains(nameToFind)) {
        foundContact = contact;
      }
    });

    return foundContact;
  }

  Future<void> _makePhoneCall(String phoneNumber, String contactName) async {
    _flutterTts.speak("Llamando a $contactName");
    await launchUrl(Uri.parse("tel:$phoneNumber"));
  }

  void _sendMessageToContact(String contactName) {
    Contact? contact = _findContactByName(contactName);

    if (contact != null && contact.phones!.isNotEmpty) {
      _promptMessageContent(contact.phones!.first.value!, contact.displayName!);
    } else {
      _flutterTts.speak("No se encontró el contacto $contactName en la lista o no tiene número de teléfono.");
    }
  }

  void _promptMessageContent(String phoneNumber, String contactName) {
    _flutterTts.speak("¿Qué mensaje deseas enviar a $contactName?");

    try {
      _speech.listen(
        onResult: (val) {
          if (val.finalResult) {
            String messageContent = val.recognizedWords;
            _sendSms(phoneNumber, messageContent, contactName);
          }
        },
      );
    } catch (e) {
      print("Error al escuchar el contenido del mensaje: $e");
    }
  }

  Future<void> _sendSms(String phoneNumber, String messageContent, String contactName) async {
    String uri = "sms:$phoneNumber?body=$messageContent";
    if (await canLaunch(uri)) {
      await launch(uri);
      _flutterTts.speak("Mensaje enviado a $contactName: $messageContent");
    } else {
      _flutterTts.speak("No se pudo enviar el mensaje.");
    }
  }

  void _openCamera() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      _flutterTts.speak("Foto capturada exitosamente.");
    } else {
      _flutterTts.speak("No se capturó ninguna foto.");
    }
  }

  String _getFormattedDate() {
    return "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return "${now.hour}:${now.minute.toString().padLeft(2, '0')}";
  }


// Future<void> _launchURL(String url) async {
//   try {
//     final bool nativeAppLaunchSucceeded = await launch(
//       url,
//       forceSafariVC: false,
//       forceWebView: false,
//       enableJavaScript: true,
//       webOnlyWindowName: 'AIDVOICE',
//       universalLinksOnly: true,
//     );
//     if (!nativeAppLaunchSucceeded) {
//       await launch(url, forceSafariVC: true, forceWebView: false);
//     }
//   } catch (e) {
//     print('Error al lanzar la URL: $e');
//     // Manejar el error según sea necesario
//   }
// }

 Future _launchURL(String url) async {
    if (Platform.isAndroid) {
      final AndroidIntent intent = AndroidIntent(
        action: 'action_view',
        data: url,
      );
      await intent.launch();
    } else {
      // Manejar el caso de iOS o cualquier otro sistema operativo aquí
      print('Este ejemplo solo es para Android.');
    }
  }


  Future<void> _showInstructions() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Instrucciones"),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text("Comandos disponibles:"),
                Text("• Abrir Facebook"),
                Text("• Abrir Instagram"),
                Text("• Abrir Snapchat"),
                Text("• Reproducir música"),
                Text("• Abrir YouTube"),
                Text("• Abrir calendario"),
                Text("• Abrir cámara"),
                Text("• Llamar a [nombre del contacto]"),
                Text("• Enviar mensaje a [nombre del contacto]"),
                Text("• Hola"),
                Text("• Cómo estás"),
                Text("• Qué haces"),
                Text("• Adiós"),
                Text("• Cuál es tu nombre"),
                Text("• Qué día es hoy"),
                Text("• Qué hora es"),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Cerrar"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AidVoice'),
      ),
      body: Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Text(
              '$_text',
              style: const TextStyle(fontSize: 24.0),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _conversation.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_conversation[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
