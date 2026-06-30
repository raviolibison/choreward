import 'package:flutter/material.dart';
import 'family_service.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _familyService = FamilyService();
  final _nameController = TextEditingController();
  final _inviteController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _createHousehold() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a family name');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await _familyService.createHousehold(_nameController.text.trim());
      if (!mounted) return;
      final context = this.context;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Household Created!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share these codes with your family:'),
              const SizedBox(height: 16),
              const Text('Child invite code:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(result['childInviteCode'], style: const TextStyle(fontSize: 24, letterSpacing: 4)),
              const SizedBox(height: 12),
              const Text('Co-parent invite code:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(result['householdInviteCode'], style: const TextStyle(fontSize: 24, letterSpacing: 4)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
    setState(() => _isLoading = false);
  }

  Future<void> _joinWithCode() async {
  if (_inviteController.text.trim().isEmpty) {
    setState(() => _errorMessage = 'Please enter an invite code');
    return;
  }
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });
  try {
    await _familyService.joinWithCode(_inviteController.text.trim());
    // No manual navigation needed — RoleRouter's StreamBuilder detects the
    // householdIds update and switches to ParentScreen/ChildScreen automatically.
  } catch (e) {
    if (mounted) setState(() => _errorMessage = e.toString());
  }
  if (mounted) setState(() => _isLoading = false);
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Choreward'),
      automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Set up your household',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            // Create household section
            const Text('Create a new household', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Family name',
                border: OutlineInputBorder(),
                hintText: 'e.g. The Karlsson Family',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _createHousehold,
              child: const Text('Create Household'),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),

            // Join section
            const Text('Join an existing household', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _inviteController,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                border: OutlineInputBorder(),
                hintText: 'Enter your 6-character code',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
                onPressed: _isLoading ? null : _joinWithCode,
                child: const Text('Join Household'),
              ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],

            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}