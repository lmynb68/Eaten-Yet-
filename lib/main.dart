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
    debugShowCheckedModeBanner: false, title: '吃什么',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffbf552f)),
      scaffoldBackgroundColor: const Color(0xfffffaf3),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      cardTheme: const CardThemeData(elevation: 0, color: Colors.white)),
    home: const CampusHome())));
}
