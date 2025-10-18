const admin = require('firebase-admin');

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON before running this script.');
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

async function testRadioQuery() {
  const store = admin.firestore();
  try {
    const snapshot = await store.collectionGroup('media')
      .where('isRadioEligible', '==', true)
      .where('isShared', '==', true)
      .where('format', '==', 'audio')
      .limit(1)
      .get();

    console.log(`Fetched ${snapshot.size} docs`);
    snapshot.forEach(doc => {
      console.log('Doc path:', doc.ref.path);
    });
  } catch (error) {
    console.error('Query failed:', error.message);
  }
}

async function testRadioQueue() {
  const store = admin.firestore();
  try {
    const snapshot = await store.collection('radioQueue')
      .orderBy('updatedAt', 'desc')
      .limit(1)
      .get();

    console.log(`radioQueue docs: ${snapshot.size}`);
    snapshot.forEach(doc => {
      console.log('radioQueue doc:', doc.id, doc.data());
    });
  } catch (error) {
    console.error('radioQueue query failed:', error.message);
  }
}

(async () => {
  await testRadioQueue();
  await testRadioQuery();
})();
