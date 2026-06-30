import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'reward_service.dart';

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

        final chores = snapshot.data?.docs ?? [];

        if (chores.isEmpty) {
          return const Center(
            child: Text(
              'No chores yet!\nCheck back later.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
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
            if (claimedByOther) {
              icon = Icons.lock;
              iconColor = Colors.grey;
            } else if (status == 'pending') {
              icon = Icons.radio_button_unchecked;
              iconColor = Colors.grey;
            } else if (status == 'submitted') {
              icon = Icons.hourglass_empty;
              iconColor = Colors.orange;
            } else if (status == 'approved') {
              icon = Icons.check_circle;
              iconColor = Colors.green;
            } else {
              icon = Icons.cancel;
              iconColor = Colors.red;
            }

            final String subtitle;
            if (status == 'pending') {
              subtitle = 'Tap to submit proof';
            } else if (status == 'submitted' && isMySubmission) {
              subtitle = 'Waiting for approval...';
            } else if (claimedByOther) {
              subtitle =
                  'Claimed by ${chore['submittedByName'] ?? 'another child'}';
            } else if (status == 'approved') {
              subtitle = 'Approved! +${chore['points']} pts';
            } else {
              subtitle = 'Rejected — tap to try again';
            }

            final tappable = status == 'pending' || status == 'rejected';

            return Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: Icon(icon, color: iconColor),
                title: Text(
                  chore['title'],
                  style: TextStyle(
                    decoration: status == 'approved'
                        ? TextDecoration.lineThrough
                        : null,
                    color: claimedByOther ? Colors.grey : null,
                  ),
                ),
                subtitle: Text(
                  subtitle,
                  style:
                      TextStyle(color: claimedByOther ? Colors.grey : null),
                ),
                trailing: Text(
                  '${chore['points']} pts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: claimedByOther ? Colors.grey : null,
                  ),
                ),
                onTap: tappable
                    ? () => _submitProof(choreId, chore['title'], householdId)
                    : null,
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
          return const Center(
            child: Text(
              'No rewards available yet.\nAsk your parent to add some!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: rewards.length,
          itemBuilder: (context, index) {
            final reward = rewards[index].data() as Map<String, dynamic>;
            final rewardId = rewards[index].id;
            final pointCost = reward['pointCost'] as int;
            final canAfford = currentPoints >= pointCost;

            return Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: Icon(
                  Icons.star,
                  color: canAfford ? Colors.amber : Colors.grey,
                ),
                title: Text(reward['title']),
                subtitle: Text(
                  canAfford
                      ? 'You can afford this!'
                      : 'Need ${pointCost - currentPoints} more points',
                  style: TextStyle(
                    color: canAfford ? Colors.green : Colors.grey,
                  ),
                ),
                trailing: ElevatedButton(
                  onPressed: canAfford
                      ? () => _redeemReward(rewardId, reward['title'],
                          pointCost, householdId, currentPoints)
                      : null,
                  child: Text('$pointCost pts'),
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

        final householdId = householdIds.first as String;
        final points = userData['points'] as int? ?? 0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Choreward'),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Center(
                  child: Text(
                    '⭐ $points pts',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
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
          body: _currentTab == 0
              ? _buildChoresTab(householdId)
              : _buildRewardsTab(householdId, points),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (index) => setState(() => _currentTab = index),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.list),
                label: 'Chores',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.star),
                label: 'Rewards',
              ),
            ],
          ),
        );
      },
    );
  }
}
