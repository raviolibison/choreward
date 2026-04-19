import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

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
      'householdInviteCode': householdInviteCode, // for adding co-parents
      'childInviteCode': childInviteCode,          // for linking a child from another household
      'createdAt': FieldValue.serverTimestamp(),
      'parentIds': [user.uid],
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

    final userDoc = await _db.collection('users').doc(user.uid).get();

    if (userDoc.exists) {
      await _db.collection('users').doc(user.uid).update({
        'householdIds': FieldValue.arrayUnion([householdId]),
      });
    } else {
      await _db.collection('users').doc(user.uid).set({
        'name': user.displayName ?? 'Child',
        'email': user.email,
        'role': 'child',
        'householdIds': [householdId],
        'points': 0,
      });
    }

    await _db.collection('households').doc(householdId).update({
      'childIds': FieldValue.arrayUnion([user.uid]),
    });
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

    final userDoc = await _db.collection('users').doc(user.uid).get();

    if (userDoc.exists) {
      await _db.collection('users').doc(user.uid).update({
        'householdIds': FieldValue.arrayUnion([householdId]),
      });
    } else {
      await _db.collection('users').doc(user.uid).set({
        'name': user.displayName ?? 'Parent',
        'email': user.email,
        'role': 'parent',
        'householdIds': [householdId],
      });
    }

    await _db.collection('households').doc(householdId).update({
      'parentIds': FieldValue.arrayUnion([user.uid]),
    });
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