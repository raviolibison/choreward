import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'family_service.dart';
import 'messaging_service.dart';
import 'reward_service.dart';

class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});

  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  final _familyService = FamilyService();
  final _rewardService = RewardService();
  final _db = FirebaseFirestore.instance;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _householdData;
  bool _isLoading = true;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    MessagingService.initialize();
  }

  Future<void> _loadData() async {
    final userData = await _familyService.getUserData();
    if (userData == null) return;
    final householdId = (userData['householdIds'] as List).first;
    final householdDoc = await _db.collection('households').doc(householdId).get();
    setState(() {
      _userData = userData;
      _householdData = householdDoc.data();
      _isLoading = false;
    });
  }

  void _showInviteCodes() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Codes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Child invite code:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Text(
                  _householdData?['childInviteCode'] ?? '',
                  style: const TextStyle(fontSize: 24, letterSpacing: 4),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _householdData?['childInviteCode'] ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied!')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Co-parent invite code:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Text(
                  _householdData?['householdInviteCode'] ?? '',
                  style: const TextStyle(fontSize: 24, letterSpacing: 4),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _householdData?['householdInviteCode'] ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied!')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAddChoreDialog(String householdId) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    int points = 10;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Chore'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Chore title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Points: '),
                  Expanded(
                    child: Slider(
                      value: points.toDouble(),
                      min: 5,
                      max: 100,
                      divisions: 19,
                      label: points.toString(),
                      onChanged: (value) {
                        setDialogState(() => points = value.toInt());
                      },
                    ),
                  ),
                  Text('$points'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;
                await _db
                    .collection('households')
                    .doc(householdId)
                    .collection('chores')
                    .add({
                  'title': titleController.text.trim(),
                  'description': descriptionController.text.trim(),
                  'points': points,
                  'status': 'pending',
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRewardDialog(String householdId) {
    final titleController = TextEditingController();
    int pointCost = 20;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Reward'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Reward title',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Extra screen time',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Cost: '),
                  Expanded(
                    child: Slider(
                      value: pointCost.toDouble(),
                      min: 5,
                      max: 200,
                      divisions: 39,
                      label: '$pointCost pts',
                      onChanged: (value) {
                        setDialogState(() => pointCost = value.toInt());
                      },
                    ),
                  ),
                  Text('$pointCost'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;
                await _rewardService.addReward(
                  householdId,
                  titleController.text.trim(),
                  pointCost,
                );
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _reviewProof(BuildContext context, String choreId, Map<String, dynamic> chore) {
    final householdId = (_userData!['householdIds'] as List).first;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(chore['title']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Proof submitted:'),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                chore['proofUrl'],
                height: 200,
                width: 250,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text('Award ${chore['points']} points upon approval'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _db
                  .collection('households')
                  .doc(householdId)
                  .collection('chores')
                  .doc(choreId)
                  .update({'status': 'rejected'});
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              final submittedBy = chore['submittedBy'];
              final points = chore['points'] as int;
              await _db
                  .collection('households')
                  .doc(householdId)
                  .collection('chores')
                  .doc(choreId)
                  .update({'status': 'approved'});
              await _db.collection('users').doc(submittedBy).update({
                'points': FieldValue.increment(points),
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Approve ✓'),
          ),
        ],
      ),
    );
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
              'No chores yet!\nTap + to add your first chore.',
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
            return Dismissible(
              key: Key(choreId),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                if (status == 'submitted') {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Chore?'),
                      content: const Text(
                          'This chore has pending proof. Deleting it will discard the submission.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                }
                return true;
              },
              onDismissed: (_) => _db
                  .collection('households')
                  .doc(householdId)
                  .collection('chores')
                  .doc(choreId)
                  .delete(),
              child: Card(
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
                  title: Text(chore['title']),
                  subtitle: Text(
                    status == 'pending'
                        ? 'Waiting for child to complete'
                        : status == 'submitted'
                            ? 'Proof submitted — tap to review'
                            : status == 'approved'
                                ? 'Approved ✓'
                                : 'Rejected',
                  ),
                  trailing: Text(
                    '${chore['points']} pts',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: status == 'submitted'
                      ? () => _reviewProof(context, choreId, chore)
                      : null,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRewardsTab(String householdId) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _rewardService.getRewards(householdId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final rewards = snapshot.data?.docs ?? [];
              if (rewards.isEmpty) {
                return const Center(
                  child: Text(
                    'No rewards yet!\nTap + to add a reward.',
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
                  return Dismissible(
                    key: Key(rewardId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _db
                        .collection('households')
                        .doc(householdId)
                        .collection('rewards')
                        .doc(rewardId)
                        .delete(),
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading:
                            const Icon(Icons.star, color: Colors.amber),
                        title: Text(reward['title']),
                        trailing: Text(
                          '${reward['pointCost']} pts',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const Text('Redemption requests:', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: StreamBuilder<QuerySnapshot>(
            stream: _rewardService.getRedemptions(householdId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final redemptions = snapshot.data?.docs ?? [];
              if (redemptions.isEmpty) {
                return const Center(
                  child: Text('No redemption requests yet.', style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.builder(
                itemCount: redemptions.length,
                itemBuilder: (context, index) {
                  final redemption = redemptions[index].data() as Map<String, dynamic>;
                  final status = redemption['status'] ?? 'pending';
                  return ListTile(
                    title: Text(redemption['rewardTitle']),
                    subtitle: Text('By ${redemption['redeemedByName']}'),
                    trailing: status == 'pending'
                        ? ElevatedButton(
                            onPressed: () async {
                              await _db
                                  .collection('households')
                                  .doc(householdId)
                                  .collection('redemptions')
                                  .doc(redemptions[index].id)
                                  .update({'status': 'fulfilled'});
                            },
                            child: const Text('Mark Done'),
                          )
                        : const Icon(Icons.check, color: Colors.green),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final householdId = (_userData!['householdIds'] as List).first;

    return Scaffold(
      appBar: AppBar(
        title: Text(_householdData?['name'] ?? 'My Household'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: _showInviteCodes,
            tooltip: 'Invite codes',
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
          : _buildRewardsTab(householdId),
      floatingActionButton: FloatingActionButton(
        onPressed: _currentTab == 0
            ? () => _showAddChoreDialog(householdId)
            : () => _showAddRewardDialog(householdId),
        child: const Icon(Icons.add),
      ),
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