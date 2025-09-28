const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const { Timestamp, FieldValue } = require('firebase/firestore');

(async () => {
  const rules = readFileSync('FirestoreRules.txt', 'utf8');
  const projectId = 'punch-in-eng-test';
  const ownerId = 'owner123';
  const engineerId = 'engineer456';
  const studioId = 'studioA';

  const env = await initializeTestEnvironment({
    projectId,
    firestore: { rules }
  });

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`studios/${studioId}`).set({
      ownerId,
      name: 'Studio A'
    });
    await db.doc(`studios/${studioId}/engineerRequests/${engineerId}`).set({
      engineerId,
      studioOwnerId: ownerId,
      status: 'pending',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now()
    });
  });

  const ownerDb = env.authenticatedContext(ownerId).firestore();
  const engineerDb = env.authenticatedContext(engineerId).firestore();

  try {
    await assertSucceeds(ownerDb.doc(`studios/${studioId}/engineerRequests/${engineerId}`).get());
    console.log('Owner can read request');
  } catch (err) {
    console.error('Owner read failed', err);
  }

  try {
    await assertSucceeds(ownerDb.collection(`studios/${studioId}/engineerRequests`).get());
    console.log('Owner can list requests');
  } catch (err) {
    console.error('Owner list failed', err);
  }

  try {
    await assertSucceeds(ownerDb.doc(`studios/${studioId}/engineerRequests/${engineerId}`).update({
      status: 'accepted',
      updatedAt: Timestamp.now()
    }));
    console.log('Owner can accept request');
  } catch (err) {
    console.error('Owner update failed', err);
  }

  try {
    await assertSucceeds(engineerDb.doc(`studios/${studioId}/engineerRequests/${engineerId}`).get());
    console.log('Engineer can read own request');
  } catch (err) {
    console.error('Engineer read failed', err);
  }

  try {
    await assertFails(engineerDb.doc(`studios/${studioId}/engineerRequests/${engineerId}`).update({
      status: 'accepted',
      updatedAt: Timestamp.now()
    }));
    console.log('Engineer cannot change status to accepted');
  } catch (err) {
    console.error('Engineer update unexpectedly succeeded', err);
  }

  await env.cleanup();
})();
