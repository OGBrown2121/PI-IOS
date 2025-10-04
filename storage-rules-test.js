const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');

(async () => {
  const firestoreRules = readFileSync('FirestoreRules.txt', 'utf8');
  const storageRules = readFileSync('FirebaseStorageRules.txt', 'utf8');
  const projectId = 'punch-in-storage-test';
  const studioId = '957C0B35-8D23-40E8-BC04-858B34588541';
  const ownerId = 'owner-123';
  const otherId = 'engineer-456';

  const env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: firestoreRules
    },
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: storageRules
    }
  });

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`studios/${studioId}`).set({
      ownerId,
      name: 'Rule Test Studio'
    });
  });

  const ownerStorage = env.authenticatedContext(ownerId).storage();
  const otherStorage = env.authenticatedContext(otherId).storage();

  try {
    await assertSucceeds(
      ownerStorage.ref(`users/${ownerId}/studios/${studioId}/logo.jpg`).putString('data', 'raw', {
        contentType: 'image/jpeg'
      })
    );
    await assertSucceeds(
      ownerStorage.ref(`users/${ownerId}/studios/${studioId}/logo.png`).putString('data', 'raw', {
        contentType: 'image/png'
      })
    );
    console.log('Owner uploads for .jpg and .png succeeded as expected');
  } catch (err) {
    console.error('Owner upload failed unexpectedly', err);
  }

  try {
    await assertFails(
      otherStorage.ref(`users/${ownerId}/studios/${studioId}/logo.jpg`).putString('data', 'raw', {
        contentType: 'image/jpeg'
      })
    );
    await assertFails(
      otherStorage.ref(`users/${ownerId}/studios/${studioId}/logo.png`).putString('data', 'raw', {
        contentType: 'image/png'
      })
    );
    console.log('Non-owner uploads denied as expected');
  } catch (err) {
    console.error('Non-owner upload unexpectedly succeeded', err);
  }

  await env.cleanup();
})();
