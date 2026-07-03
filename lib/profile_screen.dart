import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: db.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snap.data!.data() as Map<String, dynamic>?;
          if (user == null) return const Center(child: CircularProgressIndicator());

          final householdIds = List<String>.from(user['householdIds'] ?? []);
          final role = user['role'] as String? ?? 'child';
          final name = user['name'] as String? ?? '';
          final email = user['email'] as String? ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _UserCard(name: name, email: email, role: role),
              const SizedBox(height: 24),
              if (householdIds.isNotEmpty) ...[
                const Text(
                  'Household',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ...householdIds.map(
                  (hid) => _HouseholdCard(householdId: hid, role: role),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String name, email, role;
  const _UserCard({required this.name, required this.email, required this.role});

  @override
  Widget build(BuildContext context) {
    final isParent = role == 'parent';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: isParent ? Colors.blue[100] : Colors.green[100],
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isParent ? Colors.blue[800] : Colors.green[800],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(isParent ? 'Parent' : 'Child'),
                    backgroundColor: isParent ? Colors.blue[100] : Colors.green[100],
                    labelStyle: TextStyle(
                      color: isParent ? Colors.blue[800] : Colors.green[800],
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HouseholdCard extends StatefulWidget {
  final String householdId;
  final String role;
  const _HouseholdCard({required this.householdId, required this.role});

  @override
  State<_HouseholdCard> createState() => _HouseholdCardState();
}

class _HouseholdCardState extends State<_HouseholdCard> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<Map<String, String>> _fetchNames(List<String> uids) async {
    if (uids.isEmpty) return {};
    final docs = await Future.wait(uids.map((u) => _db.collection('users').doc(u).get()));
    return Map.fromEntries(
      docs.where((d) => d.exists).map(
            (d) => MapEntry(d.id, (d.data()?['name'] as String?) ?? 'Unknown'),
          ),
    );
  }

  Future<void> _rename(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Household'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == currentName) return;
    await _db.collection('households').doc(widget.householdId).update({'name': newName});
  }

  Future<void> _leave(List<String> parentIds) async {
    final uid = _auth.currentUser!.uid;
    final isLastParent =
        widget.role == 'parent' && parentIds.length == 1 && parentIds.contains(uid);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Household?'),
        content: Text(
          isLastParent
              ? 'You are the only parent. Leaving will make this household unmanaged. Are you sure?'
              : 'You will lose access to this household\'s chores and rewards. You can rejoin with an invite code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final arrayField = widget.role == 'parent' ? 'parentIds' : 'childIds';
    await _db.collection('households').doc(widget.householdId).update({
      arrayField: FieldValue.arrayRemove([uid]),
    });
    await _db.collection('users').doc(uid).update({
      'householdIds': FieldValue.arrayRemove([widget.householdId]),
    });

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _auth.currentUser!.uid;
    final isParent = widget.role == 'parent';

    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('households').doc(widget.householdId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snap.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox.shrink();

        final householdName = data['name'] as String? ?? 'My Household';
        final isPremium = data['isPremium'] == true;
        final parentIds = List<String>.from(data['parentIds'] ?? []);
        final childIds = List<String>.from(data['childIds'] ?? []);
        final childCode = data['childInviteCode'] as String? ?? '';
        final parentCode = data['householdInviteCode'] as String? ?? '';

        return FutureBuilder<Map<String, String>>(
          future: _fetchNames([...parentIds, ...childIds]),
          builder: (context, namesSnap) {
            final names = namesSnap.data ?? {};

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row
                    Row(
                      children: [
                        const Icon(Icons.home_outlined, color: Colors.deepPurple),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            householdName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isParent)
                          isPremium
                              ? IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Rename',
                                  onPressed: () => _rename(householdName),
                                )
                              : Tooltip(
                                  message: 'Premium feature',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.lock, size: 14, color: Colors.grey),
                                      SizedBox(width: 2),
                                      Text(
                                        'Rename',
                                        style: TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                      ],
                    ),

                    const Divider(height: 24),

                    // Members
                    const Text(
                      'MEMBERS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    ...parentIds.map((uid) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.blue[100],
                            child: Text(
                              (names[uid] ?? 'P')[0].toUpperCase(),
                              style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                            ),
                          ),
                          title: Text(
                            uid == currentUid
                                ? '${names[uid] ?? 'Parent'} (You)'
                                : names[uid] ?? 'Parent',
                          ),
                          trailing: const Text(
                            'Parent',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )),
                    ...childIds.map((uid) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.green[100],
                            child: Text(
                              (names[uid] ?? 'C')[0].toUpperCase(),
                              style: TextStyle(fontSize: 13, color: Colors.green[800]),
                            ),
                          ),
                          title: Text(
                            uid == currentUid
                                ? '${names[uid] ?? 'Child'} (You)'
                                : names[uid] ?? 'Child',
                          ),
                          trailing: const Text(
                            'Child',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )),

                    // Invite codes (parents only)
                    if (isParent) ...[
                      const Divider(height: 24),
                      const Text(
                        'INVITE CODES',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      _CodeRow(label: 'Child', code: childCode, onCopy: () => _copy(childCode)),
                      const SizedBox(height: 4),
                      _CodeRow(label: 'Co-parent', code: parentCode, onCopy: () => _copy(parentCode)),
                    ],

                    const Divider(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.exit_to_app, color: Colors.red),
                        label: const Text(
                          'Leave Household',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () => _leave(parentIds),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CodeRow extends StatelessWidget {
  final String label, code;
  final VoidCallback onCopy;
  const _CodeRow({required this.label, required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label:', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(width: 8),
        Text(
          code,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 3),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: onCopy,
          tooltip: 'Copy',
        ),
      ],
    );
  }
}
