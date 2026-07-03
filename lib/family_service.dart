import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class PremiumLimitException implements Exception {
  final String message;
  const PremiumLimitException(this.message);
  @override
  String toString() => message;
}

const _maxFreeParents = 2;
const _maxFreeChildren = 3;

class FamilyService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
  }

  // Called when a parent creates a new household
  Future<Map<String, dynamic>> createHousehold(String familyName) async {
    final user = _auth.currentUser!;
    final householdInviteCode = _generateInviteCode();
    final childInviteCode = _generateInviteCode();

    final householdRef = await _db.collection('households').add({
      'name': familyName,
      'householdInviteCode': householdInviteCode,
      'childInviteCode': childInviteCode,
      'createdAt': FieldValue.serverTimestamp(),
      'parentIds': [user.uid],
      'childIds': [],
      'isPremium': false,
    });

    // Create the user document
    await _db.collection('users').doc(user.uid).set({
      'name': user.displayName ?? 'Parent',
      'email': user.email,
      'role': 'parent',
      'householdIds': [householdRef.id],
    });

    return {
      'householdId': householdRef.id,
      'householdInviteCode': householdInviteCode,
      'childInviteCode': childInviteCode,
    };
  }

  Future<void> joinHouseholdAsChild(String inviteCode) async {
    final user = _auth.currentUser!;

    final query = await _db
        .collection('households')
        .where('childInviteCode', isEqualTo: inviteCode.toUpperCase())
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Invalid invite code');
    }

    final household = query.docs.first;
    final householdId = household.id;
    final householdData = household.data();

    final isPremium = householdData['isPremium'] == true;
    final currentChildren = List<String>.from(householdData['childIds'] ?? []);
    if (!isPremium && currentChildren.length >= _maxFreeChildren) {
      throw const PremiumLimitException('children');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();

    await _db.collection('households').doc(householdId).update({
      'childIds': FieldValue.arrayUnion([user.uid]),
    });

    if (userDoc.exists) {
      final updates = <String, dynamic>{
        'householdIds': FieldValue.arrayUnion([householdId]),
      };
      if (userDoc.data()?['role'] == null) {
        updates['role'] = 'child';
      }
      await _db.collection('users').doc(user.uid).update(updates);
    } else {
      await _db.collection('users').doc(user.uid).set({
        'name': user.displayName ?? 'Child',
        'email': user.email,
        'role': 'child',
        'householdIds': [householdId],
        'points': 0,
      });
    }
  }

  Future<void> joinHouseholdAsParent(String inviteCode) async {
    final user = _auth.currentUser!;

    final query = await _db
        .collection('households')
        .where('householdInviteCode', isEqualTo: inviteCode.toUpperCase())
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Invalid invite code');
    }

    final household = query.docs.first;
    final householdId = household.id;
    final householdData = household.data();

    final isPremium = householdData['isPremium'] == true;
    final currentParents = List<String>.from(householdData['parentIds'] ?? []);
    if (!isPremium && currentParents.length >= _maxFreeParents) {
      throw const PremiumLimitException('parents');
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();

    await _db.collection('households').doc(householdId).update({
      'parentIds': FieldValue.arrayUnion([user.uid]),
    });

    if (userDoc.exists) {
      await _db.collection('users').doc(user.uid).update({
        'householdIds': FieldValue.arrayUnion([householdId]),
        'role': 'parent',
      });
    } else {
      await _db.collection('users').doc(user.uid).set({
        'name': user.displayName ?? 'Parent',
        'email': user.email,
        'role': 'parent',
        'householdIds': [householdId],
      });
    }
  }

  Future<void> joinWithCode(String inviteCode) async {
  final code = inviteCode.toUpperCase().trim();

  // Check if it's a child invite code
  final childQuery = await _db
      .collection('households')
      .where('childInviteCode', isEqualTo: code)
      .get();

  if (childQuery.docs.isNotEmpty) {
    await joinHouseholdAsChild(code);
    return;
  }

  // Check if it's a co-parent invite code
  final parentQuery = await _db
      .collection('households')
      .where('householdInviteCode', isEqualTo: code)
      .get();

  if (parentQuery.docs.isNotEmpty) {
    await joinHouseholdAsParent(code);
    return;
  }

  throw Exception('Invalid invite code');
}

  // Get current user data
  Future<Map<String, dynamic>?> getUserData() async {
    final user = _auth.currentUser!;
    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.data();
  }
}