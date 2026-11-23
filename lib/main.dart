import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0C10),
        textTheme: GoogleFonts.manropeTextTheme(Theme.of(context).textTheme),
      ),
      home: const DashboardScreen(),
    );
  }
}

class ServerProfile {
  final String url;
  final String remark;
  final String host;
  final int port;
  int pingMs;

  ServerProfile({
    required this.url,
    required this.remark,
    required this.host,
    required this.port,
    this.pingMs = 9999,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FlutterV2ray _v2ray = FlutterV2ray(onStatusChanged: (status) {});
  bool isConnected = false;
  String currentServer = "Не выбран";
  int currentPing = 0;
  bool isLoading = false;
  String loadingText = "Подключение...";

  // ВСТАВЬ СЮДА СВОЮ ССЫЛКУ НА ПОДПИСКУ ИЗ БОТА
  final String subscriptionUrl = "https://твой-сайт.com/api/sub/твой-токен"; 

  Future<void> connectToBestServer() async {
    setState(() {
      isLoading = true;
      loadingText = "Загрузка подписки...";
    });

    try {
      final response = await http.get(Uri.parse(subscriptionUrl));
      final decoded = utf8.decode(base64.decode(response.body.trim()));
      
      List<ServerProfile> servers = [];
      final lines = decoded.split('\n');
      
      for (String line in lines) {
        if (line.startsWith('vless://')) {
          final uri = Uri.parse(line);
          final remark = uri.fragment.isNotEmpty ? uri.fragment : "Server";
          final host = uri.host;
          final port = uri.port;
          
          servers.add(ServerProfile(url: line, remark: remark, host: host, port: port));
        }
      }

      if (servers.isEmpty) throw Exception("В подписке нет VLESS серверов");

      setState(() => loadingText = "Тестирование пинга...");

      await Future.wait(servers.map((server) async {
        server.pingMs = await _tcpPing(server.host, server.port);
      }));

      servers.removeWhere((s) => s.pingMs == -1); 
      servers.sort((a, b) => a.pingMs.compareTo(b.pingMs));

      if (servers.isEmpty) throw Exception("Все серверы недоступны");

      final bestServer = servers.first;

      setState(() => loadingText = "Запуск туннеля...");

      final parser = V2raySubscriptionParser();
      final parsedServer = parser.parse(bestServer.url);
      
      await _v2ray.initializeV2ray();
      await _v2ray.startV2ray(
        remark: bestServer.remark,
        config: parsedServer.getFullConfiguration(),
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
      );
      
      setState(() {
        isConnected = true;
        currentServer = bestServer.remark;
        currentPing = bestServer.pingMs;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<int> _tcpPing(String host, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return -1; 
    }
  }

  void disconnect() async {
    await _v2ray.stopV2ray();
    setState(() => isConnected = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF111827), Color(0xFF0A0C10)],
            center: Alignment.topCenter,
            radius: 1.5,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("TUNNED VPN", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isConnected ? Colors.greenAccent.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isConnected ? "● $currentServer | ${currentPing}ms" : "○ Отключено",
                        style: TextStyle(color: isConnected ? Colors.greenAccent : Colors.redAccent, fontSize: 12),
                      ),
                    )
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: isLoading ? null : (isConnected ? disconnect : connectToBestServer),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
                    border: Border.all(
                      color: isConnected ? Colors.cyanAccent : Colors.white24,
                      width: 2,
                    ),
                    boxShadow: isConnected ? [
                      BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 40, spreadRadius: 10)
                    ] : [],
                  ),
                  child: Center(
                    child: isLoading 
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: Colors.cyanAccent),
                            const SizedBox(height: 16),
                            Text(loadingText, style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                          ],
                        )
                      : Icon(
                          Icons.shield_outlined,
                          size: 80,
                          color: isConnected ? Colors.cyanAccent : Colors.white54,
                        ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildBottomIcon(Icons.flash_on, "Авто", Colors.cyanAccent),
                          _buildBottomIcon(Icons.dns, "Серверы", Colors.white54),
                          _buildBottomIcon(Icons.settings, "Настройки", Colors.white54),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomIcon(IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}
