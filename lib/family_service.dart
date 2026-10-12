import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PremiumLimitException implements Exception {
  final String message;
  const PremiumLimitException(this.message);
  @override
  String toString() => message;
}

// A user may belong to multiple households. `activeHouseholdId` on the user
// doc records which one is currently selected; falls back to the first
// household if unset or stale (e.g. the user left that household).
String resolveActiveHouseholdId(Map<String, dynamic> userData) {
  final householdIds = List<String>.from(userData['householdIds'] ?? []);
  final active = userData['activeHouseholdId'] as String?;
  if (active != null && householdIds.contains(active)) return active;
  return householdIds.first;
}

class FamilyService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Server-side so a household can't be created with isPremium already set,
  // and so invite codes are stored where only parents can read them — see
  // createHousehold in functions/index.js.
  Future<Map<String, dynamic>> createHousehold(String familyName) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createHousehold')
          .call({'name': familyName});
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not create household');
    }
  }

  // Joining a household requires proving possession of an invite code,
  // which can only be verified server-side — Firestore rules can't check a
  // code that isn't part of the write being made. This calls the
  // `joinHousehold` Cloud Function, which validates the code and premium
  // limits with Admin privileges and writes both documents atomically.
  Future<void> joinWithCode(String inviteCode) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('joinHousehold')
          .call({'inviteCode': inviteCode.toUpperCase().trim()});
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw PremiumLimitException(e.message ?? 'members');
      }
      throw Exception(e.message ?? 'Invalid invite code');
    }
  }

  // Server-side, since it has to delete the Auth user and clean up other
  // members' data — see deleteAccount in functions/index.js.
  Future<void> deleteAccount() async {
    await FirebaseFunctions.instance.httpsCallable('deleteAccount').call();
  }

  // Get current user data
  Future<Map<String, dynamic>?> getUserData() async {
    final user = _auth.currentUser!;
    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.data();
  }
}