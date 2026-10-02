const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

const TIERS = [
  { min: 10, type: 'referral_crown_black_gold', title: 'Black + Gold Crown', description: 'Black + Gold Crown • 10 qualified referrals.' },
  { min: 5, type: 'referral_crown_gold', title: 'Golden Crown', description: 'Golden Crown • 5 qualified referrals.' },
  { min: 3, type: 'referral_crown_purple', title: 'Purple Crown', description: 'Purple Crown • 3 qualified referrals.' },
  { min: 1, type: 'referral_crown_blue', title: 'Blue Crown', description: 'Blue Crown • 1 qualified referral.' },
];

function tierForCount(count) {
  return TIERS.find((tier) => count >= tier.min) || null;
}

/**
 * Issues a referral-crown reward only when the backend-controlled qualified
 * referral count moves into a new crown tier. The client cannot create the
 * entitlement or Mail record; Firestore rules keep those paths backend-owned.
 */
exports.issueReferralCrownReward = onDocumentUpdated('users/{uid}', async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data() || {};
  const beforeProfile = before.alphaDenProfile || {};
  const afterProfile = after.alphaDenProfile || {};
  const beforeCount = Number(beforeProfile.referrals || 0);
  const afterCount = Number(afterProfile.referrals || 0);

  if (!Number.isFinite(afterCount) || afterCount <= beforeCount) return null;

  const tier = tierForCount(afterCount);
  if (!tier) return null;

  const userRef = db.collection('users').doc(event.params.uid);
  const entitlementRef = userRef.collection('badgeEntitlements').doc(tier.type);
  const mailRef = userRef.collection('mail').doc(`reward_${tier.type}`);

  await db.runTransaction(async (tx) => {
    const entitlementSnap = await tx.get(entitlementRef);
    const existing = entitlementSnap.exists ? entitlementSnap.data() : null;

    if (!existing) {
      tx.create(entitlementRef, {
        badgeId: tier.type,
        badgeType: tier.type,
        eligible: true,
        status: 'available',
        referralCount: afterCount,
        title: tier.title,
        description: tier.description,
        source: 'referral_crown',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const mailSnap = await tx.get(mailRef);
    if (!mailSnap.exists) {
      tx.create(mailRef, {
        type: 'badge',
        title: `${tier.title} Reward Available`,
        body: `You reached ${tier.min} qualified referral${tier.min === 1 ? '' : 's'} and earned your ${tier.title}. Open this reward to collect it, preview your Alpha Den profile, and confirm the badge.`,
        badgeIds: [tier.type],
        referralCount: afterCount,
        readAt: null,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  });

  return null;
});
