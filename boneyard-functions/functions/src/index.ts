import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

// ✅ Trigger whenever a user adds, updates, or deletes a log
export const updateClimbStats = functions.firestore
  .document("climbs/{climbId}/logs/{logId}")
  .onWrite(async (change, context) => {
    const { climbId } = context.params;
    const logsRef = db.collection(`climbs/${climbId}/logs`);

    try {
      // Fetch all logs for this climb
      const logsSnap = await logsRef.get();
      let totalRating = 0;
      let count = 0;

      logsSnap.forEach(doc => {
        const data = doc.data();
        if (data.rating != null) {
          totalRating += data.rating;
          count++;
        }
      });

      const avgRating = count > 0 ? totalRating / count : 0;

      // Update climb document
      const climbRef = db.collection("climbs").doc(climbId);
      await climbRef.update({
        ascentCount: count,
        avgRating: avgRating,
      });

      console.log(`✅ Updated climb ${climbId}: ascents=${count}, avg=${avgRating.toFixed(2)}`);
    } catch (err) {
      console.error("❌ Failed to update climb stats:", err);
    }
  });
