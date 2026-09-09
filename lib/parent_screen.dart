import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'family_service.dart';
import 'messaging_service.dart';
import 'profile_screen.dart';
import 'reward_service.dart';

const _forest = Color(0xFF2D6A4F);
const _amber = Color(0xFFF59E0B);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);

Color _statusColor(String status) => switch (status) {
  'submitted' => const Color(0xFFD97706),
  'approved' => _green,
  'rejected' => _red,
  _ => _forest,
};

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
  Map<String, String> _childNames = {};
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
    final householdId = resolveActiveHouseholdId(userData);
    final householdDoc = await _db
        .collection('households')
        .doc(householdId)
        .get();
    final householdData = householdDoc.data();

    final childIds = List<String>.from(householdData?['childIds'] ?? []);
    final childDocs = await Future.wait(
      childIds.map((uid) => _db.collection('users').doc(uid).get()),
    );
    final childNames = Map.fromEntries(
      childDocs
          .where((d) => d.exists)
          .map(
            (d) => MapEntry(d.id, (d.data()?['name'] as String?) ?? 'Child'),
          ),
    );

    setState(() {
      _userData = userData;
      _householdData = householdData;
      _childNames = childNames;
      _isLoading = false;
    });
  }

  void _showChoreDialog(
    String householdId, {
    String? choreId,
    Map<String, dynamic>? existing,
  }) {
    final isEditing = choreId != null;
    final titleController = TextEditingController(
      text: existing?['title'] as String? ?? '',
    );
    final descriptionController = TextEditingController(
      text: existing?['description'] as String? ?? '',
    );
    int points = existing?['points'] as int? ?? 10;
    String? assignedTo = existing?['assignedTo'] as String?;
    bool isRecurring = existing?['isRecurring'] == true;
    String recurrenceType = existing?['recurrenceType'] as String? ?? 'weekly';
    List<int> recurrenceDays = existing?['recurrenceType'] == 'weekly'
        ? List<int>.from(existing?['recurrenceDays'] ?? [])
        : [];
    int monthlyDay =
        existing?['recurrenceType'] == 'monthly' &&
            (existing?['recurrenceDays'] as List?)?.isNotEmpty == true
        ? (existing!['recurrenceDays'] as List).first as int
        : 1;
    String? weeklyError;
    final isPremium = _householdData?['isPremium'] == true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Chore' : 'Add Chore'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        onChanged: (value) =>
                            setDialogState(() => points = value.toInt()),
                      ),
                    ),
                    Text('$points'),
                  ],
                ),
                const SizedBox(height: 4),

                // Assign to child
                if (isPremium && _childNames.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: assignedTo,
                    decoration: const InputDecoration(
                      labelText: 'Assign to',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All children'),
                      ),
                      ..._childNames.entries.map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => assignedTo = v),
                  )
                else
                  Opacity(
                    opacity: isPremium ? 0.4 : 0.5,
                    child: Row(
                      children: [
                        const Icon(Icons.lock, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          isPremium
                              ? 'No children in household yet'
                              : 'Assign to specific child',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Spacer(),
                        if (!isPremium)
                          const Chip(
                            label: Text(
                              'Premium',
                              style: TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),

                // Recurrence — premium-gated
                if (isPremium) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Repeating chore',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: isRecurring
                        ? Text(
                            _recurrenceSummary(
                              recurrenceType,
                              recurrenceDays,
                              monthlyDay,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          )
                        : null,
                    value: isRecurring,
                    activeThumbColor: _forest,
                    onChanged: (v) => setDialogState(() {
                      isRecurring = v;
                      recurrenceDays = [];
                      weeklyError = null;
                    }),
                  ),
                  if (isRecurring) ...[
                    const SizedBox(height: 4),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'daily',
                          label: Text('Daily', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'weekly',
                          label: Text('Weekly', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'monthly',
                          label: Text(
                            'Monthly',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      selected: {recurrenceType},
                      onSelectionChanged: (s) => setDialogState(() {
                        recurrenceType = s.first;
                        recurrenceDays = [];
                        weeklyError = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (recurrenceType == 'weekly') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(7, (i) {
                          final selected = recurrenceDays.contains(i);
                          return GestureDetector(
                            onTap: () => setDialogState(() {
                              weeklyError = null;
                              if (selected) {
                                recurrenceDays = recurrenceDays
                                    .where((d) => d != i)
                                    .toList();
                              } else {
                                recurrenceDays = [...recurrenceDays, i];
                              }
                            }),
                            child: CircleAvatar(
                              radius: 17,
                              backgroundColor: selected
                                  ? _forest
                                  : const Color(0xFFECFDF5),
                              child: Text(
                                ['S', 'M', 'T', 'W', 'T', 'F', 'S'][i],
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      if (weeklyError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            weeklyError!,
                            style: const TextStyle(color: _red, fontSize: 12),
                          ),
                        ),
                    ] else if (recurrenceType == 'monthly') ...[
                      Row(
                        children: [
                          const Text(
                            'Day of month:',
                            style: TextStyle(fontSize: 13),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            color: _forest,
                            onPressed: monthlyDay > 1
                                ? () => setDialogState(() => monthlyDay--)
                                : null,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '$monthlyDay',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _forest,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: _forest,
                            onPressed: monthlyDay < 28
                                ? () => setDialogState(() => monthlyDay++)
                                : null,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ],
                  ],
                ] else ...[
                  Opacity(
                    opacity: 0.5,
                    child: Row(
                      children: const [
                        Icon(Icons.repeat_rounded, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Repeating chores',
                          style: TextStyle(fontSize: 13),
                        ),
                        Spacer(),
                        Chip(
                          label: Text(
                            'Premium',
                            style: TextStyle(fontSize: 11),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;
                if (isRecurring &&
                    recurrenceType == 'weekly' &&
                    recurrenceDays.isEmpty) {
                  setDialogState(() => weeklyError = 'Select at least one day');
                  return;
                }
                final choresRef = _db
                    .collection('households')
                    .doc(householdId)
                    .collection('chores');
                final fields = {
                  'title': titleController.text.trim(),
                  'description': descriptionController.text.trim(),
                  'points': points,
                  'assignedTo': assignedTo,
                  'isRecurring': isRecurring,
                  'recurrenceType': isRecurring ? recurrenceType : null,
                  'recurrenceDays': isRecurring
                      ? (recurrenceType == 'monthly'
                            ? [monthlyDay]
                            : List<int>.from(recurrenceDays))
                      : null,
                };
                if (isEditing) {
                  await choresRef.doc(choreId).update(fields);
                } else {
                  await choresRef.add({
                    ...fields,
                    'status': 'pending',
                    'nextDueAt': null,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }
                if (mounted) Navigator.pop(context);
              },
              child: Text(isEditing ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRewardDialog(
    String householdId, {
    String? rewardId,
    Map<String, dynamic>? existing,
  }) {
    final isEditing = rewardId != null;
    final titleController = TextEditingController(
      text: existing?['title'] as String? ?? '',
    );
    int pointCost = existing?['pointCost'] as int? ?? 20;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Reward' : 'Add Reward'),
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
                if (isEditing) {
                  await _rewardService.updateReward(
                    householdId,
                    rewardId,
                    titleController.text.trim(),
                    pointCost,
                  );
                } else {
                  await _rewardService.addReward(
                    householdId,
                    titleController.text.trim(),
                    pointCost,
                  );
                }
                if (mounted) Navigator.pop(context);
              },
              child: Text(isEditing ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _reviewProof(
    BuildContext context,
    String choreId,
    Map<String, dynamic> chore,
  ) {
    final householdId = resolveActiveHouseholdId(_userData!);
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
            child: const Text('Reject', style: TextStyle(color: _red)),
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

  String _choreSubtitle(Map<String, dynamic> chore, String status) {
    final assignedTo = chore['assignedTo'] as String?;
    final namePrefix = assignedTo != null
        ? 'For ${_childNames[assignedTo] ?? 'child'} — '
        : '';
    final isRecurring = chore['isRecurring'] == true;

    final nextDueRaw = chore['nextDueAt'];
    if (nextDueRaw != null && status == 'pending') {
      final dueDate = (nextDueRaw as Timestamp).toDate();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      if (dueDate.isAfter(todayStart)) {
        return 'Next due ${_formatDueDate(dueDate)}';
      }
    }

    final recurringPrefix = isRecurring ? '↻ ' : '';
    return switch (status) {
      'submitted' => '${namePrefix}Tap to review proof',
      'approved' => 'Approved ✓',
      'rejected' => 'Rejected',
      _ => '$recurringPrefix${namePrefix}Waiting for completion',
    };
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'today';
    if (dateOnly == tomorrow) return 'tomorrow';
    const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekDays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }

  String _recurrenceSummary(String type, List<int> days, int monthlyDay) {
    const weekDayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return switch (type) {
      'daily' => 'Every day',
      'weekly' =>
        days.isEmpty
            ? 'Pick days below'
            : 'Every ${days.map((d) => weekDayNames[d]).join(', ')}',
      'monthly' => 'On the ${_ordinal(monthlyDay)} of each month',
      _ => '',
    };
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_task_rounded, size: 56, color: Colors.grey[300]),
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
                Text(
                  'Tap + to add your first chore.',
                  style: TextStyle(color: Colors.grey[400]),
                ),
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
            final isRecurring = chore['isRecurring'] == true;
            final nextDueRaw = chore['nextDueAt'];
            final nextDueAt = nextDueRaw != null
                ? (nextDueRaw as Timestamp).toDate()
                : null;
            final now = DateTime.now();
            final isScheduled =
                nextDueAt != null &&
                nextDueAt.isAfter(DateTime(now.year, now.month, now.day));
            final sc = isScheduled
                ? const Color(0xFFD1D5DB)
                : _statusColor(status);
            return Dismissible(
              key: Key(choreId),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_rounded, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                if (status == 'submitted') {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Chore?'),
                      content: const Text(
                        'This chore has pending proof. Deleting it will discard the submission.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                          ),
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
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(width: 4, color: sc),
                      Expanded(
                        child: InkWell(
                          onTap: status == 'submitted'
                              ? () => _reviewProof(context, choreId, chore)
                              : () => _showChoreDialog(
                                  householdId,
                                  choreId: choreId,
                                  existing: chore,
                                ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              chore['title'],
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                                color: isScheduled
                                                    ? Colors.grey[400]
                                                    : null,
                                              ),
                                            ),
                                          ),
                                          if (isRecurring)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4,
                                              ),
                                              child: Icon(
                                                Icons.repeat_rounded,
                                                size: 14,
                                                color: isScheduled
                                                    ? Colors.grey[300]
                                                    : Colors.grey[400],
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _choreSubtitle(chore, status),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isScheduled
                                              ? Colors.grey[400]
                                              : sc,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${chore['points']} pts',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: _amber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.card_giftcard_rounded,
                        size: 56,
                        color: Colors.grey[300],
                      ),
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
                      Text(
                        'Tap + to add a reward.',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
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
                  return Dismissible(
                    key: Key(rewardId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(
                        Icons.delete_rounded,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) => _db
                        .collection('households')
                        .doc(householdId)
                        .collection('rewards')
                        .doc(rewardId)
                        .delete(),
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showRewardDialog(
                          householdId,
                          rewardId: rewardId,
                          existing: reward,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.star_rounded,
                                  color: _amber,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  reward['title'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${reward['pointCost']} pts',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: _amber,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.inbox_rounded, size: 18, color: _forest),
              const SizedBox(width: 6),
              Text(
                'Redemption requests',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                ),
              ),
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
                return Center(
                  child: Text(
                    'No redemption requests yet.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: redemptions.length,
                itemBuilder: (context, index) {
                  final redemption =
                      redemptions[index].data() as Map<String, dynamic>;
                  final status = redemption['status'] ?? 'pending';
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: status == 'pending'
                            ? const Color(0xFFFFFBEB)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        status == 'pending'
                            ? Icons.star_rounded
                            : Icons.check_circle_rounded,
                        color: status == 'pending' ? _amber : _green,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      redemption['rewardTitle'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      'By ${redemption['redeemedByName']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
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
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(fontSize: 12),
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded, color: _green),
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

    final householdId = resolveActiveHouseholdId(_userData!);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _householdData?['name'] ?? 'My Household',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              // Picks up a household switch made on the Profile screen.
              if (mounted) _loadData();
            },
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
      body: _currentTab == 0
          ? _buildChoresTab(householdId)
          : _buildRewardsTab(householdId),
      floatingActionButton: FloatingActionButton(
        onPressed: _currentTab == 0
            ? () => _showChoreDialog(householdId)
            : () => _showRewardDialog(householdId),
        child: const Icon(Icons.add_rounded),
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
  }
}
