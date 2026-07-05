import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const _forest = Color(0xFF2D6A4F);
const _deepForest = Color(0xFF1B4332);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);

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
                  'HOUSEHOLD',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7C3AED),
                    letterSpacing: 1.2,
                  ),
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
    final avatarBg = isParent ? const Color(0xFFDCFCE7) : const Color(0xFFD1FAE5);
    final avatarFg = isParent ? _deepForest : _green;
    final chipBg = isParent ? const Color(0xFFDCFCE7) : const Color(0xFFD1FAE5);
    final chipFg = isParent ? _deepForest : _green;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: avatarBg,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: avatarFg,
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
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isParent ? 'Parent' : 'Child',
                      style: TextStyle(
                        color: chipFg,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
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
              backgroundColor: _red,
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.home_rounded, color: _forest, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            householdName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isParent)
                          isPremium
                              ? IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: _forest),
                                  tooltip: 'Rename',
                                  onPressed: () => _rename(householdName),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.lock_outline, size: 14, color: Color(0xFF9CA3AF)),
                                    SizedBox(width: 2),
                                    Text(
                                      'Rename',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                    ),
                                  ],
                                ),
                      ],
                    ),

                    const Divider(height: 28),

                    const Text(
                      'MEMBERS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _forest,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...parentIds.map((uid) => _MemberTile(
                          uid: uid,
                          name: uid == currentUid
                              ? '${names[uid] ?? 'Parent'} (You)'
                              : names[uid] ?? 'Parent',
                          role: 'Parent',
                          isParent: true,
                        )),
                    ...childIds.map((uid) => _MemberTile(
                          uid: uid,
                          name: uid == currentUid
                              ? '${names[uid] ?? 'Child'} (You)'
                              : names[uid] ?? 'Child',
                          role: 'Child',
                          isParent: false,
                        )),

                    if (isParent) ...[
                      const Divider(height: 28),
                      const Text(
                        'INVITE CODES',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _forest,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CodeRow(label: 'Child', code: childCode, onCopy: () => _copy(childCode)),
                      const SizedBox(height: 6),
                      _CodeRow(label: 'Co-parent', code: parentCode, onCopy: () => _copy(parentCode)),
                    ],

                    const Divider(height: 28),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.exit_to_app_rounded, color: _red),
                        label: const Text(
                          'Leave Household',
                          style: TextStyle(color: _red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _red),
                          foregroundColor: _red,
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

class _MemberTile extends StatelessWidget {
  final String uid, name, role;
  final bool isParent;
  const _MemberTile({
    required this.uid,
    required this.name,
    required this.role,
    required this.isParent,
  });

  @override
  Widget build(BuildContext context) {
    final avatarBg = isParent ? const Color(0xFFDCFCE7) : const Color(0xFFD1FAE5);
    final avatarFg = isParent ? _deepForest : _green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: avatarBg,
            child: Text(
              name[0].toUpperCase(),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: avatarFg),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: avatarBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role,
              style: TextStyle(fontSize: 11, color: avatarFg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final String label, code;
  final VoidCallback onCopy;
  const _CodeRow({required this.label, required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.w500),
          ),
          Text(
            code,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: _forest,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onCopy,
            child: const Icon(Icons.copy_rounded, size: 18, color: _forest),
          ),
        ],
      ),
    );
  }
}
