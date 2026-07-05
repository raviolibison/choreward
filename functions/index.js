const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

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
