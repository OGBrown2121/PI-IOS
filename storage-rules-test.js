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

  try {
    await assertSucceeds(
      ownerStorage.ref(`users/${ownerId}/media/media-123/track.mp3`).putString('audio-bytes', 'raw', {
        contentType: 'audio/mpeg'
      })
    );
    await assertSucceeds(
      ownerStorage.ref(`users/${ownerId}/media/media-123/video.mp4`).putString('video-bytes', 'raw', {
        contentType: 'video/mp4'
      })
    );
    console.log('Owner media uploads succeeded as expected');
  } catch (err) {
    console.error('Owner media upload failed unexpectedly', err);
  }

  try {
    await assertFails(
      otherStorage.ref(`users/${ownerId}/media/media-abc/track.mp3`).putString('audio-bytes', 'raw', {
        contentType: 'audio/mpeg'
      })
    );
    console.log('Non-owner media uploads denied as expected');
  } catch (err) {
    console.error('Non-owner media upload unexpectedly succeeded', err);
  }

  const reportId = 'report-123';
  const evidencePath = `user-reports/${ownerId}/${reportId}/evidence/photo.jpg`;
  try {
    await assertSucceeds(
      ownerStorage.ref(evidencePath).putString('evidence-bytes', 'raw', {
        contentType: 'image/jpeg'
      })
    );
    console.log('Reporter evidence upload succeeded as expected');
  } catch (err) {
    console.error('Reporter evidence upload failed unexpectedly', err);
  }

  try {
    await assertFails(
      otherStorage.ref(evidencePath).putString('evidence-bytes', 'raw', {
        contentType: 'image/jpeg'
      })
    );
    console.log('Non-reporter evidence upload denied as expected');
  } catch (err) {
    console.error('Non-reporter evidence upload unexpectedly succeeded', err);
  }

  try {
    await assertFails(otherStorage.ref(evidencePath).delete());
    console.log('Non-reporter evidence delete denied as expected');
  } catch (err) {
    console.error('Non-reporter evidence delete unexpectedly succeeded', err);
  }

  try {
    await assertSucceeds(ownerStorage.ref(evidencePath).delete());
    console.log('Reporter evidence delete succeeded as expected');
  } catch (err) {
    console.error('Reporter evidence delete failed unexpectedly', err);
  }

  await env.cleanup();
})();
