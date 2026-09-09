import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'family_service.dart';
import 'messaging_service.dart';
import 'profile_screen.dart';
import 'reward_service.dart';

const _forest = Color(0xFF2D6A4F);
const _amber = Color(0xFFF59E0B);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);

class ChildScreen extends StatefulWidget {
  const ChildScreen({super.key});

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen> {
  final _rewardService = RewardService();
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    MessagingService.initialize();
  }

  Future<void> _submitProof(
      String choreId, String choreTitle, String householdId) async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;

    final user = _auth.currentUser!;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Uploading proof...'),
          ],
        ),
      ),
    );

    try {
      final ref = _storage
          .ref()
          .child('proof')
          .child(householdId)
          .child('$choreId-${DateTime.now().millisecondsSinceEpoch}.jpg');

      await ref.putFile(File(picked.path));
      final downloadUrl = await ref.getDownloadURL();

      final choreRef = _db
          .collection('households')
          .doc(householdId)
          .collection('chores')
          .doc(choreId);

      await _db.runTransaction((transaction) async {
        final choreDoc = await transaction.get(choreRef);
        final currentStatus = choreDoc.data()?['status'];
        if (currentStatus != 'pending' && currentStatus != 'rejected') {
          throw Exception('This chore was just claimed by someone else.');
        }
        transaction.update(choreRef, {
          'status': 'submitted',
          'proofUrl': downloadUrl,
          'submittedBy': user.uid,
          'submittedByName': user.displayName ?? 'Child',
          'submittedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Proof submitted for "$choreTitle"!')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _redeemReward(String rewardId, String rewardTitle, int pointCost,
      String householdId, int currentPoints) async {
    if (currentPoints < pointCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough points!')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem Reward?'),
        content: Text('Spend $pointCost points on "$rewardTitle"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redeem!'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _rewardService.redeemReward(
          householdId, rewardId, rewardTitle, pointCost);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Redeemed "$rewardTitle"! Your parent will be notified.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _statusChip(String status, bool isMySubmission, bool claimedByOther) {
    if (claimedByOther) {
      return _chip('Claimed', const Color(0xFF6B7280), const Color(0xFFF3F4F6));
    }
    return switch (status) {
      'submitted' => _chip('Pending review', const Color(0xFFD97706), const Color(0xFFFFFBEB)),
      'approved'  => _chip('Approved ✓', _green, const Color(0xFFECFDF5)),
      'rejected'  => _chip('Try again', _red, const Color(0xFFFEF2F2)),
      _           => _chip('Tap to complete', _forest, const Color(0xFFF0FDF4)),
    };
  }

  Widget _chip(String label, Color textColor, Color bgColor) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildPointsHeader(int points, String name) {
    final firstName = name.split(' ').first;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2D6A4F), Color(0xFF1B4332)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hi $firstName! 👋',
            style: const TextStyle(
              color: Color(0xFFDDD6FE),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$points',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '⭐ points',
                  style: TextStyle(color: Color(0xFFDDD6FE), fontSize: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChoresTab(String householdId) {
    final currentUserId = _auth.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('households')
          .doc(householdId)
          .collection('chores')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final chores = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // Assignment filter
          final assignedTo = data['assignedTo'] as String?;
          if (assignedTo != null && assignedTo != currentUserId) return false;

          // Recurring: hide until nextDueAt
          final nextDueRaw = data['nextDueAt'];
          if (nextDueRaw != null) {
            final dueDate = (nextDueRaw as Timestamp).toDate();
            final today = DateTime.now();
            final todayStart = DateTime(today.year, today.month, today.day);
            if (dueDate.isAfter(todayStart)) return false;
          }

          return true;
        }).toList();

        if (chores.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.task_alt_rounded, size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'No chores yet!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 4),
                Text('Check back later.', style: TextStyle(color: Colors.grey[400])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: chores.length,
          itemBuilder: (context, index) {
            final chore = chores[index].data() as Map<String, dynamic>;
            final choreId = chores[index].id;
            final status = chore['status'] as String? ?? 'pending';
            final submittedBy = chore['submittedBy'] as String?;
            final isMySubmission = submittedBy == currentUserId;
            final claimedByOther = status == 'submitted' && !isMySubmission;

            final IconData icon;
            final Color iconColor;
            final Color iconBgColor;

            if (claimedByOther) {
              icon = Icons.lock_outline_rounded;
              iconColor = const Color(0xFF9CA3AF);
              iconBgColor = const Color(0xFFF3F4F6);
            } else if (status == 'pending') {
              icon = Icons.circle_outlined;
              iconColor = _forest;
              iconBgColor = const Color(0xFFF0FDF4);
            } else if (status == 'submitted') {
              icon = Icons.hourglass_top_rounded;
              iconColor = const Color(0xFFD97706);
              iconBgColor = const Color(0xFFFFFBEB);
            } else if (status == 'approved') {
              icon = Icons.check_circle_rounded;
              iconColor = _green;
              iconBgColor = const Color(0xFFECFDF5);
            } else {
              icon = Icons.cancel_rounded;
              iconColor = _red;
              iconBgColor = const Color(0xFFFEF2F2);
            }

            final tappable = status == 'pending' || status == 'rejected';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: tappable
                    ? () => _submitProof(choreId, chore['title'], householdId)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: iconBgColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: iconColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chore['title'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                decoration: status == 'approved'
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: claimedByOther ? Colors.grey[400] : null,
                              ),
                            ),
                            _statusChip(status, isMySubmission, claimedByOther),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: claimedByOther
                              ? const Color(0xFFF3F4F6)
                              : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '+${chore['points']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: claimedByOther ? Colors.grey[400] : _amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRewardsTab(String householdId, int currentPoints) {
    return StreamBuilder<QuerySnapshot>(
      stream: _rewardService.getRewards(householdId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final rewards = snapshot.data?.docs ?? [];

        if (rewards.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.card_giftcard_rounded, size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'No rewards yet!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 4),
                Text('Ask your parent to add some.',
                    style: TextStyle(color: Colors.grey[400])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rewards.length,
          itemBuilder: (context, index) {
            final reward = rewards[index].data() as Map<String, dynamic>;
            final rewardId = rewards[index].id;
            final pointCost = reward['pointCost'] as int;
            final canAfford = currentPoints >= pointCost;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: canAfford
                            ? const Color(0xFFFFFBEB)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.star_rounded,
                        color: canAfford ? _amber : Colors.grey[400],
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reward['title'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            canAfford
                                ? 'You can afford this! 🎉'
                                : 'Need ${pointCost - currentPoints} more pts',
                            style: TextStyle(
                              fontSize: 12,
                              color: canAfford ? _green : Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: canAfford
                          ? () => _redeemReward(rewardId, reward['title'],
                              pointCost, householdId, currentPoints)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canAfford ? _amber : Colors.grey[200],
                        foregroundColor: canAfford ? Colors.white : Colors.grey[500],
                        disabledBackgroundColor: Colors.grey[200],
                        disabledForegroundColor: Colors.grey[400],
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '$pointCost pts',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
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

  @override
  Widget build(BuildContext context) {
    final userId = _auth.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(userId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        if (userData == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final householdIds = userData['householdIds'] as List?;
        if (householdIds == null || householdIds.isEmpty) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final householdId = resolveActiveHouseholdId(userData);
        final points = userData['points'] as int? ?? 0;
        final name = userData['name'] as String? ?? '';

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Choreward',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline_rounded),
                tooltip: 'Profile',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  await GoogleSignIn().signOut();
                  if (mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
              ),
            ],
          ),
          body: Column(
            children: [
              _buildPointsHeader(points, name),
              Expanded(
                child: _currentTab == 0
                    ? _buildChoresTab(householdId)
                    : _buildRewardsTab(householdId, points),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (index) => setState(() => _currentTab = index),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.task_alt_rounded),
                label: 'Chores',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.card_giftcard_rounded),
                label: 'Rewards',
              ),
            ],
          ),
        );
      },
    );
  }
}
