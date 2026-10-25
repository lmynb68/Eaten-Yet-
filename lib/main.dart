import 'package:flutter/material.dart';
import 'home.dart';
import 'language.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const EatWhatApp()); }
class EatWhatApp extends StatefulWidget {
  const EatWhatApp({super.key});
  @override
  State<EatWhatApp> createState() => _EatWhatAppState();
}
class _EatWhatAppState extends State<EatWhatApp> {
  final language = LanguageController();
  @override
  void initState() { super.initState(); language.load(); }
  @override
  void dispose() { language.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => LanguageScope(controller: language, child: ListenableBuilder(listenable: language, builder: (context, _) => MaterialApp(
    locale: Locale(language.code), supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false, title: '吃了么',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff914f35), surface: Colors.white),
      scaffoldBackgroundColor: const Color(0xfff5f6f7),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff5f6f7), surfaceTintColor: Colors.transparent, elevation: 0),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: Color(0xfff7eee8), height: 72),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xffe9eae5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xffe9eae5)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: const Color(0xff914f35), foregroundColor: Colors.white,
        minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
      chipTheme: ChipThemeData(showCheckmark: false, backgroundColor: Colors.white, selectedColor: const Color(0xfff7eee8),
        side: const BorderSide(color: Color(0xffe9eae5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 6)),
      cardTheme: CardThemeData(elevation: 0, color: Colors.white, margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
    home: const CampusHome())));
}
