const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
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
      // Notify all parents in the household
      const householdSnap = await db.collection("households").doc(householdId).get();
      const parentIds = householdSnap.data()?.parentIds ?? [];
      const tokens = await getTokens(db, parentIds);
      if (tokens.length === 0) return;

      await notify(tokens, {
        title: "Proof submitted! 📸",
        body: `${after.submittedByName ?? "Your child"} completed "${after.title}"`,
      });

    } else if (after.status === "approved" || after.status === "rejected") {
      // Notify the child who submitted the proof
      const submittedBy = after.submittedBy;
      if (!submittedBy) return;

      const tokens = await getTokens(db, [submittedBy]);
      if (tokens.length === 0) return;

      const approved = after.status === "approved";
      await notify(tokens, {
        title: approved ? "Chore approved! 🎉" : "Chore rejected",
        body: approved
          ? `You earned ${after.points} points for "${after.title}"!`
          : `"${after.title}" was rejected. Tap to try again.`,
      });
    }
  }
);

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
    android: { priority: "high" },
    apns: { payload: { aps: { sound: "default" } } },
  });

  // Log any failed sends (invalid tokens etc.)
  response.responses.forEach((r, i) => {
    if (!r.success) {
      console.error(`Token ${i} failed:`, r.error?.message);
    }
  });
}
