const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const { Timestamp } = require('firebase/firestore');

(async () => {
  const rules = readFileSync('FirestoreRules.txt', 'utf8');
  const projectId = 'punch-in-chat-test';

  const env = await initializeTestEnvironment({
    projectId,
    firestore: { rules }
  });

  const authedUid = 'XfXeWoFZMLTPoEIXtWae4wRgpl33';
  const otherUid = 'hED5RhZ9tJZGpfZCVcAtUGdfpAn2';

  const authedDb = env.authenticatedContext(authedUid).firestore();
  const docRef = authedDb.doc(`conversations/test-thread`);

  const participantPayload = {
    id: authedUid,
    type: 'user',
    username: 'testuser',
    displayName: 'Test User',
    accountType: 'artist',
    profileImageURL: null,
    createdAt: Timestamp.now(),
    profileDetails: {
      bio: '',
      fieldOne: '',
      fieldTwo: ''
    }
  };

  const otherParticipantPayload = {
    id: otherUid,
    type: 'user',
    username: 'otheruser',
    displayName: 'Other User',
    accountType: 'artist',
    profileImageURL: null,
    createdAt: Timestamp.now(),
    profileDetails: {
      bio: '',
      fieldOne: '',
      fieldTwo: ''
    }
  };

  const payload = {
    creatorId: authedUid,
    kind: 'direct',
    participantIds: [authedUid, otherUid],
    participants: [participantPayload, otherParticipantPayload],
    createdAt: Timestamp.now(),
    dataVersion: 1,
    groupSettings: null
  };

  try {
    await assertSucceeds(docRef.set(payload));
    console.log('Conversation create succeeded as expected');
  } catch (err) {
    console.error('Conversation create failed', err);
  }

  await env.cleanup();
})();
