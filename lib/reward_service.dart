import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RewardService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<void> addReward(String householdId, String title, int pointCost) async {
    await _db
        .collection('households')
        .doc(householdId)
        .collection('rewards')
        .add({
      'title': title,
      'pointCost': pointCost,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> redeemReward(String householdId, String rewardId, String rewardTitle, int pointCost) async {
    final user = _auth.currentUser!;
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final currentPoints = userDoc.data()?['points'] ?? 0;

    if (currentPoints < pointCost) {
      throw Exception('Not enough points!');
    }

    // Deduct points
    await _db.collection('users').doc(user.uid).update({
      'points': FieldValue.increment(-pointCost),
    });

    // Log the redemption
    await _db
        .collection('households')
        .doc(householdId)
        .collection('redemptions')
        .add({
      'rewardId': rewardId,
      'rewardTitle': rewardTitle,
      'pointCost': pointCost,
      'redeemedBy': user.uid,
      'redeemedByName': user.displayName ?? 'Child',
      'status': 'pending',
      'redeemedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getRewards(String householdId) {
    return _db
        .collection('households')
        .doc(householdId)
        .collection('rewards')
        .orderBy('pointCost')
        .snapshots();
  }

  Stream<QuerySnapshot> getRedemptions(String householdId) {
    return _db
        .collection('households')
        .doc(householdId)
        .collection('redemptions')
        .orderBy('redeemedAt', descending: true)
        .snapshots();
  }
}