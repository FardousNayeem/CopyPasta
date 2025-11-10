import 'package:flutter/material.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({Key? key}) : super(key: key);

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  bool isConnected = false;
  String? connectedDevice;

  // Mocked nearby devices
  List<String> nearbyDevices = [
    'CopyPasta-Phone',
    'CopyPasta-Laptop',
    'CopyPasta-Tablet'
  ];

  void connectToDevice(String deviceName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Request'),
        content: Text('Do you want to connect with "$deviceName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Connect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        isConnected = true;
        connectedDevice = deviceName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to $deviceName')),
      );

      // Return connection success to homepage
      Navigator.pop(context, true);
    }
  }

  void disconnect() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect?'),
        content: Text('Do you want to disconnect from "$connectedDevice"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                isConnected = false;
                connectedDevice = null;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Disconnected')),
              );
            },
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.primaryContainer,
        title: Text(
          'Connect Devices',
          style: TextStyle(
            color: theme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: nearbyDevices.length,
                itemBuilder: (context, index) {
                  final device = nearbyDevices[index];
                  return Card(
                    color: theme.surfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(
                        device,
                        style: TextStyle(
                          color: theme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: ElevatedButton.icon(
                        icon: const Icon(Icons.link),
                        label: const Text('Connect'),
                        onPressed: () => connectToDevice(device),
                      ),
                    ),
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
