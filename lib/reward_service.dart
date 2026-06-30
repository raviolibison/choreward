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
    final userRef = _db.collection('users').doc(user.uid);
    final redemptionRef = _db
        .collection('households')
        .doc(householdId)
        .collection('redemptions')
        .doc();

    await _db.runTransaction((transaction) async {
      final userDoc = await transaction.get(userRef);
      final currentPoints = userDoc.data()?['points'] as int? ?? 0;

      if (currentPoints < pointCost) {
        throw Exception('Not enough points!');
      }

      transaction.update(userRef, {'points': FieldValue.increment(-pointCost)});

      transaction.set(redemptionRef, {
        'rewardId': rewardId,
        'rewardTitle': rewardTitle,
        'pointCost': pointCost,
        'redeemedBy': user.uid,
        'redeemedByName': user.displayName ?? 'Child',
        'status': 'pending',
        'redeemedAt': FieldValue.serverTimestamp(),
      });
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