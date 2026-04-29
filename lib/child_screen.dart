import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'family_service.dart';
import 'reward_service.dart';

class ChildScreen extends StatefulWidget {
  const ChildScreen({super.key});

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen> {
  final _familyService = FamilyService();
  final _rewardService = RewardService();
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userData = await _familyService.getUserData();
    setState(() {
      _userData = userData;
      _isLoading = false;
    });
  }

  Future<void> _refreshPoints() async {
    final userData = await _familyService.getUserData();
    setState(() => _userData = userData);
  }

  Future<void> _submitProof(String choreId, String choreTitle) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;

    final householdId = (_userData!['householdIds'] as List).first;
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

      await _db
          .collection('households')
          .doc(householdId)
          .collection('chores')
          .doc(choreId)
          .update({
        'status': 'submitted',
        'proofUrl': downloadUrl,
        'submittedBy': user.uid,
        'submittedAt': FieldValue.serverTimestamp(),
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

  Future<void> _redeemReward(String rewardId, String rewardTitle, int pointCost) async {
    final householdId = (_userData!['householdIds'] as List).first;
    final currentPoints = _userData?['points'] ?? 0;

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
      await _rewardService.redeemReward(householdId, rewardId, rewardTitle, pointCost);
      await _refreshPoints();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Redeemed "$rewardTitle"! Your parent will be notified.')),
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
            final status = chore['status'] ?? 'pending';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: Icon(
                  status == 'pending'
                      ? Icons.radio_button_unchecked
                      : status == 'submitted'
                          ? Icons.hourglass_empty
                          : status == 'approved'
                              ? Icons.check_circle
                              : Icons.cancel,
                  color: status == 'pending'
                      ? Colors.grey
                      : status == 'submitted'
                          ? Colors.orange
                          : status == 'approved'
                              ? Colors.green
                              : Colors.red,
                ),
                title: Text(
                  chore['title'],
                  style: TextStyle(
                    decoration: status == 'approved'
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(
                  status == 'pending'
                      ? 'Tap to submit proof'
                      : status == 'submitted'
                          ? 'Waiting for approval...'
                          : status == 'approved'
                              ? 'Approved! +${chore['points']} pts'
                              : 'Rejected — try again',
                ),
                trailing: Text(
                  '${chore['points']} pts',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: status == 'pending' || status == 'rejected'
                    ? () => _submitProof(choreId, chore['title'])
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRewardsTab(String householdId) {
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
            final currentPoints = _userData?['points'] ?? 0;
            final canAfford = currentPoints >= pointCost;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: Icon(
                  Icons.star,
                  color: canAfford ? Colors.amber : Colors.grey,
                ),
                title: Text(reward['title']),
                subtitle: Text(
                  canAfford ? 'You can afford this!' : 'Need ${pointCost - currentPoints} more points',
                  style: TextStyle(
                    color: canAfford ? Colors.green : Colors.grey,
                  ),
                ),
                trailing: ElevatedButton(
                  onPressed: canAfford
                      ? () => _redeemReward(rewardId, reward['title'], pointCost)
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final householdId = (_userData!['householdIds'] as List).first;
    final points = _userData?['points'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choreward'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Text(
                '⭐ $points pts',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              await GoogleSignIn().signOut();
            },
          ),
        ],
      ),
      body: _currentTab == 0
          ? _buildChoresTab(householdId)
          : _buildRewardsTab(householdId),
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
  }
}