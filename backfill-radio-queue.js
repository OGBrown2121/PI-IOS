const admin = require('firebase-admin');

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS.');
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

async function backfill() {
  const db = admin.firestore();
  console.log('Scanning for radio-eligible media...');
  const snapshot = await db.collectionGroup('media')
    .where('isRadioEligible', '==', true)
    .where('isShared', '==', true)
    .where('format', '==', 'audio')
    .get();

  console.log(`Found ${snapshot.size} radio-eligible items.`);

  const batch = db.batch();
  snapshot.forEach(doc => {
    const data = doc.data();
    const ownerId = doc.ref.parent.parent.id;
    const mediaId = doc.id;
    const docId = `${ownerId}_${mediaId}`;
    const ref = db.collection('radioQueue').doc(docId);
    batch.set(ref, {
      ownerId,
      mediaId,
      createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: data.updatedAt || admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  await batch.commit();
  console.log('Backfill complete.');
}

backfill().catch(err => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
