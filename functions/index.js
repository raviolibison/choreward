const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");
const { randomInt } = require("crypto");

initializeApp();

const MAX_FREE_PARENTS = 2;
const MAX_FREE_CHILDREN = 3;

// Must match premiumEntitlementId in lib/billing_service.dart.
const PREMIUM_ENTITLEMENT_ID = "premium";

// Set with: firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
// Then configure the same value as the "Authorization header value" for
// this webhook in the RevenueCat dashboard (Project Settings > Webhooks).
const revenueCatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

// Invite codes are stored server-only in inviteCodes/{code} -> {householdId,
// role}, and shown to parents from households/{id}/private/invites. They
// must never be on the household doc itself: every member can read that,
// and a child holding the co-parent code could join as a parent.
const INVITE_CODE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const INVITE_CODE_PATTERN = /^[A-Z0-9]{6}$/;

function generateInviteCode() {
  return Array.from({ length: 6 }, () => INVITE_CODE_CHARS[randomInt(INVITE_CODE_CHARS.length)]).join("");
}

async function pickUnusedInviteCode(tx, db, exclude) {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = generateInviteCode();
    if (code === exclude) continue;
    const snap = await tx.get(db.collection("inviteCodes").doc(code));
    if (!snap.exists) return code;
  }
  throw new HttpsError("internal", "Could not generate an invite code. Please try again.");
}

// Server-side so clients can't create a household with isPremium already set,
// or write invite codes anywhere members can read them.
exports.createHousehold = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const name = String(request.data?.name ?? "").trim();
  if (!name || name.length > 60) {
    throw new HttpsError("invalid-argument", "Please enter a family name (max 60 characters).");
  }

  const db = getFirestore();
  const householdRef = db.collection("households").doc();
  const userRef = db.collection("users").doc(uid);
  const account = await getAuth().getUser(uid);

  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const childInviteCode = await pickUnusedInviteCode(tx, db);
    const householdInviteCode = await pickUnusedInviteCode(tx, db, childInviteCode);

    tx.set(householdRef, {
      name,
      createdAt: FieldValue.serverTimestamp(),
      parentIds: [uid],
      childIds: [],
      isPremium: false,
    });
    tx.set(householdRef.collection("private").doc("invites"), { childInviteCode, householdInviteCode });
    tx.set(db.collection("inviteCodes").doc(childInviteCode), { householdId: householdRef.id, role: "child" });
    tx.set(db.collection("inviteCodes").doc(householdInviteCode), { householdId: householdRef.id, role: "parent" });

    if (userSnap.exists) {
      tx.update(userRef, {
        householdIds: FieldValue.arrayUnion(householdRef.id),
        activeHouseholdId: householdRef.id,
        role: "parent",
      });
    } else {
      tx.set(userRef, {
        name: account.displayName || "Parent",
        email: account.email ?? null,
        role: "parent",
        householdIds: [householdRef.id],
      });
    }

    return { householdId: householdRef.id, childInviteCode, householdInviteCode };
  });
});

// Joining a household requires proving possession of an invite code, which
// can only be verified server-side. This runs with Admin privileges and is
// the only way to add yourself to a household's parentIds/childIds — see
// firestore.rules.
exports.joinHousehold = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const code = String(request.data?.inviteCode ?? "").trim().toUpperCase();
  if (!INVITE_CODE_PATTERN.test(code)) {
    throw new HttpsError("not-found", "Invalid invite code.");
  }

  const db = getFirestore();
  const codeSnap = await db.collection("inviteCodes").doc(code).get();
  if (!codeSnap.exists) {
    throw new HttpsError("not-found", "Invalid invite code.");
  }

  const { householdId, role } = codeSnap.data();
  const householdRef = db.collection("households").doc(householdId);
  const userRef = db.collection("users").doc(uid);
  const account = await getAuth().getUser(uid);

  return db.runTransaction(async (tx) => {
    const [householdSnap, userSnap] = await Promise.all([
      tx.get(householdRef),
      tx.get(userRef),
    ]);
    const household = householdSnap.data();
    if (!household) {
      throw new HttpsError("not-found", "Household no longer exists.");
    }

    const idsField = role === "child" ? "childIds" : "parentIds";
    const currentIds = household[idsField] ?? [];

    if (currentIds.includes(uid)) {
      return { householdId: householdRef.id, role };
    }

    const isPremium = household.isPremium === true;
    const limit = role === "child" ? MAX_FREE_CHILDREN : MAX_FREE_PARENTS;
    if (!isPremium && currentIds.length >= limit) {
      throw new HttpsError("resource-exhausted", role === "child" ? "children" : "parents");
    }

    tx.update(householdRef, { [idsField]: FieldValue.arrayUnion(uid) });

    if (userSnap.exists) {
      const userUpdate = { householdIds: FieldValue.arrayUnion(householdRef.id) };
      if (role === "parent") {
        userUpdate.role = "parent";
      } else if (userSnap.data().role == null) {
        userUpdate.role = "child";
      }
      tx.update(userRef, userUpdate);
    } else {
      tx.set(userRef, {
        name: account.displayName || (role === "child" ? "Child" : "Parent"),
        email: account.email ?? null,
        role,
        householdIds: [householdRef.id],
        ...(role === "child" ? { points: 0 } : {}),
      });
    }

    return { householdId: householdRef.id, role };
  });
});

// Receives purchase lifecycle events from RevenueCat and flips `isPremium`
// on the household accordingly. `isPremium` must only ever be set here
// (Admin SDK, after RevenueCat has confirmed the purchase server-side) —
// never trust a client's own view of its entitlements, same reasoning as
// joinHousehold above.
//
// Identity design: RevenueCat's app_user_id is configured (see
// BillingService.configureForHousehold in the Flutter app) to be the
// household ID itself, not the purchasing user's UID — Premium is a
// household-level flag, so anyone in the household can buy it and it
// unlocks for everyone in that household.
//
// Setup: create this entitlement ("premium") and your product(s) in the
// RevenueCat dashboard, then add a Webhook (Project Settings > Webhooks)
// pointing at this function's URL, with an "Authorization header value"
// matching REVENUECAT_WEBHOOK_SECRET (see defineSecret above).
exports.revenueCatWebhook = onRequest(
  { secrets: [revenueCatWebhookSecret] },
  async (req, res) => {
    const authHeader = req.headers.authorization ?? "";
    if (authHeader !== `Bearer ${revenueCatWebhookSecret.value()}`) {
      res.status(401).send("Unauthorized");
      return;
    }

    const event = req.body?.event;
    const householdId = event?.app_user_id;
    const entitlements = event?.entitlement_ids ?? [];
    if (!event || !householdId || !entitlements.includes(PREMIUM_ENTITLEMENT_ID)) {
      res.status(200).send("Ignored (no matching entitlement)");
      return;
    }

    // CANCELLATION just disables auto-renew — access continues until
    // EXPIRATION, so it's intentionally not a revoke trigger here.
    // BILLING_ISSUE grace periods and TRANSFER need product decisions this
    // scaffold doesn't make for you; handle them explicitly before relying
    // on this in production.
    const GRANT_TYPES = new Set([
      "INITIAL_PURCHASE",
      "RENEWAL",
      "PRODUCT_CHANGE",
      "UNCANCELLATION",
      "NON_RENEWING_PURCHASE",
    ]);
    const REVOKE_TYPES = new Set(["EXPIRATION"]);

    if (!GRANT_TYPES.has(event.type) && !REVOKE_TYPES.has(event.type)) {
      res.status(200).send("Ignored (event type not handled)");
      return;
    }

    const db = getFirestore();
    const householdRef = db.collection("households").doc(householdId);
    const householdSnap = await householdRef.get();
    if (!householdSnap.exists) {
      console.error(`revenueCatWebhook: no household ${householdId} for app_user_id`);
      res.status(200).send("Ignored (unknown household)");
      return;
    }

    await householdRef.update({ isPremium: GRANT_TYPES.has(event.type) });
    res.status(200).send("OK");
  }
);

// In-app account deletion (required by Google Play for apps with accounts).
// Households the caller is the last parent of are deleted outright, for
// every member; in households that live on, the caller's membership, chore
// proof photos, and name on chores/redemptions are removed. Does not cancel a
// Google Play subscription — that has to be done in the Play Store.
exports.deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const householdIds = userSnap.data()?.householdIds ?? [];

  for (const householdId of householdIds) {
    const householdRef = db.collection("households").doc(householdId);
    const householdSnap = await householdRef.get();
    const household = householdSnap.data();
    if (!household) continue;

    const remainingParents = (household.parentIds ?? []).filter((id) => id !== uid);
    if (remainingParents.length === 0) {
      await deleteHousehold(db, householdRef, household);
    } else {
      await removeMemberFromHousehold(db, householdRef, uid);
    }
  }

  await userRef.delete();
  await getAuth().deleteUser(uid);
  return { deleted: true };
});

async function deleteHousehold(db, householdRef, household) {
  const memberRefs = [...(household.parentIds ?? []), ...(household.childIds ?? [])]
    .map((id) => db.collection("users").doc(id));
  const memberSnaps = memberRefs.length > 0 ? await db.getAll(...memberRefs) : [];
  const invitesSnap = await householdRef.collection("private").doc("invites").get();
  const invites = invitesSnap.data() ?? {};

  const batch = db.batch();
  for (const snap of memberSnaps) {
    if (snap.exists) {
      batch.update(snap.ref, { householdIds: FieldValue.arrayRemove(householdRef.id) });
    }
  }
  for (const code of [invites.childInviteCode, invites.householdInviteCode]) {
    if (code) batch.delete(db.collection("inviteCodes").doc(code));
  }
  await batch.commit();

  await db.recursiveDelete(householdRef);
  await getStorage().bucket().deleteFiles({ prefix: `proof/${householdRef.id}/` });
}

async function removeMemberFromHousehold(db, householdRef, uid) {
  const [choresSnap, redemptionsSnap] = await Promise.all([
    householdRef.collection("chores").where("submittedBy", "==", uid).get(),
    householdRef.collection("redemptions").where("redeemedBy", "==", uid).get(),
  ]);

  const bucket = getStorage().bucket();
  await Promise.all(
    choresSnap.docs
      .map((doc) => storagePathFromDownloadUrl(doc.data().proofUrl))
      .filter(Boolean)
      .map((path) => bucket.file(path).delete({ ignoreNotFound: true }))
  );

  const batch = db.batch();
  batch.update(householdRef, {
    parentIds: FieldValue.arrayRemove(uid),
    childIds: FieldValue.arrayRemove(uid),
  });
  for (const doc of choresSnap.docs) {
    const chore = doc.data();
    batch.update(doc.ref, {
      proofUrl: null,
      submittedBy: null,
      submittedByName: null,
      submittedAt: null,
      // A submission awaiting review can't be approved without its submitter.
      ...(chore.status === "submitted" ? { status: "pending" } : {}),
    });
  }
  for (const doc of redemptionsSnap.docs) {
    batch.update(doc.ref, { redeemedBy: null, redeemedByName: "Deleted user" });
  }
  await batch.commit();
}

// Firebase Storage download URLs look like
// https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<url-encoded path>?alt=media&token=...
function storagePathFromDownloadUrl(url) {
  const match = typeof url === "string" ? url.match(/\/o\/([^?]+)/) : null;
  return match ? decodeURIComponent(match[1]) : null;
}

exports.onChoreUpdated = onDocumentUpdated(
  "households/{householdId}/chores/{choreId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (!before || !after || before.status === after.status) return;

    const db = getFirestore();
    const { householdId } = event.params;

    if (after.status === "submitted") {
      const householdSnap = await db.collection("households").doc(householdId).get();
      const parentIds = householdSnap.data()?.parentIds ?? [];
      const tokens = await getTokens(db, parentIds);
      if (tokens.length === 0) return;

      await notify(tokens, {
        title: "Proof submitted! 📸",
        body: `${after.submittedByName ?? "Your child"} completed "${after.title}"`,
      });

    } else if (after.status === "approved" || after.status === "rejected") {
      const submittedBy = after.submittedBy;
      if (submittedBy) {
        const tokens = await getTokens(db, [submittedBy]);
        if (tokens.length > 0) {
          const approved = after.status === "approved";
          await notify(tokens, {
            title: approved ? "Chore approved! 🎉" : "Chore rejected",
            body: approved
              ? `You earned ${after.points} points for "${after.title}"!`
              : `"${after.title}" was rejected. Tap to try again.`,
          });
        }
      }

      // Reset recurring chore after approval
      if (
        after.status === "approved" &&
        before.status !== "approved" &&
        after.isRecurring &&
        after.recurrenceType
      ) {
        const nextDue = calculateNextDueAt(after.recurrenceType, after.recurrenceDays ?? []);
        if (nextDue) {
          await event.data.after.ref.update({
            status: "pending",
            proofUrl: null,
            submittedBy: null,
            submittedByName: null,
            submittedAt: null,
            nextDueAt: Timestamp.fromDate(nextDue),
          });
        }
      }
    }
  }
);

exports.onRedemptionCreated = onDocumentCreated(
  "households/{householdId}/redemptions/{redemptionId}",
  async (event) => {
    const redemption = event.data.data();
    if (!redemption) return;

    const db = getFirestore();
    const { householdId } = event.params;

    const householdSnap = await db.collection("households").doc(householdId).get();
    const parentIds = householdSnap.data()?.parentIds ?? [];
    const tokens = await getTokens(db, parentIds);
    if (tokens.length === 0) return;

    await notify(tokens, {
      title: "Reward redeemed! 🎁",
      body: `${redemption.redeemedByName ?? "Your child"} wants "${redemption.rewardTitle}" (${redemption.pointCost} pts)`,
    });
  }
);

// ---------------------------------------------------------------------------
// Recurrence helpers
// ---------------------------------------------------------------------------

// recurrenceDays uses JS convention: 0=Sun, 1=Mon, ..., 6=Sat
function calculateNextDueAt(recurrenceType, recurrenceDays) {
  const now = new Date();

  if (recurrenceType === "daily") {
    const next = new Date(now);
    next.setDate(next.getDate() + 1);
    next.setHours(0, 0, 0, 0);
    return next;
  }

  if (recurrenceType === "weekly") {
    if (!recurrenceDays || recurrenceDays.length === 0) return null;
    const todayDay = now.getDay(); // 0=Sun … 6=Sat
    let minDays = 7;
    for (const day of recurrenceDays) {
      let diff = (day - todayDay + 7) % 7;
      if (diff === 0) diff = 7; // already completed today — next week
      if (diff < minDays) minDays = diff;
    }
    const next = new Date(now);
    next.setDate(next.getDate() + minDays);
    next.setHours(0, 0, 0, 0);
    return next;
  }

  if (recurrenceType === "monthly") {
    const dayOfMonth = (recurrenceDays && recurrenceDays[0]) || 1;
    const todayMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    // Try the target day this month
    const thisMonth = new Date(now.getFullYear(), now.getMonth(), dayOfMonth);
    if (thisMonth > todayMidnight) return thisMonth;

    // Otherwise next month (JS handles day overflow correctly)
    return new Date(now.getFullYear(), now.getMonth() + 1, dayOfMonth);
  }

  return null;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

async function getTokens(db, userIds) {
  const results = await Promise.all(
    userIds.map((uid) => db.collection("users").doc(uid).get())
  );
  return results
    .map((snap) => snap.data()?.fcmToken)
    .filter(Boolean);
}

async function notify(tokens, notification) {
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification,
    android: {
      priority: "high",
      notification: { channelId: "chore_alerts" },
    },
    apns: { payload: { aps: { sound: "default" } } },
  });

  response.responses.forEach((r, i) => {
    if (!r.success) {
      console.error(`Token ${i} failed:`, r.error?.message);
    }
  });
}
