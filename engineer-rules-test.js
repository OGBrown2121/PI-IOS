const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const { Timestamp, FieldValue } = require('firebase/firestore');

(async () => {
  const rules = readFileSync('FirestoreRules.txt', 'utf8');
  const projectId = 'punch-in-eng-test';
  const ownerId = 'owner123';
  const engineerId = 'engineer456';
  const studioId = 'studioA';
  const artistId = 'artist789';
  const bookingId = 'booking123';

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
    await db.doc(`bookings/${bookingId}`).set({
      artistId,
      studioId,
      roomId: 'roomA',
      engineerId,
      status: 'pending',
      requestedStart: Timestamp.fromDate(new Date('2025-11-30T10:00:00Z')),
      requestedEnd: Timestamp.fromDate(new Date('2025-11-30T13:00:00Z')),
      confirmedStart: null,
      confirmedEnd: null,
      durationMinutes: 180,
      instantBook: false,
      pricing: {
        hourlyRate: 75,
        total: 225,
        currency: 'USD'
      },
      approval: {
        requiresStudioApproval: true,
        requiresEngineerApproval: true,
        resolvedBy: null,
        resolvedAt: null
      },
      notes: 'Initial booking',
      conversationId: null,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now()
    });
  });

  const ownerDb = env.authenticatedContext(ownerId).firestore();
  const engineerDb = env.authenticatedContext(engineerId).firestore();
  const artistDb = env.authenticatedContext(artistId).firestore();

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

  try {
    await assertSucceeds(engineerDb.doc(`bookings/${bookingId}`).set({
      artistId,
      studioId,
      roomId: 'roomA',
      engineerId,
      status: 'pending',
      requestedStart: Timestamp.fromDate(new Date('2025-12-01T10:00:00Z')),
      requestedEnd: Timestamp.fromDate(new Date('2025-12-01T12:00:00Z')),
      durationMinutes: 120,
      confirmedStart: FieldValue.delete(),
      confirmedEnd: FieldValue.delete(),
      instantBook: false,
      pricing: {
        hourlyRate: 75,
        total: 150,
        currency: 'USD'
      },
      approval: {
        requiresStudioApproval: true,
        requiresEngineerApproval: true,
        resolvedBy: null,
        resolvedAt: null
      },
      notes: 'Rescheduled by engineer',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now()
    }, { merge: true }));
    console.log('Engineer can reschedule booking');
  } catch (err) {
    console.error('Engineer reschedule failed', err);
  }

  try {
    await assertSucceeds(artistDb.doc(`bookings/${bookingId}`).set({
      status: 'pending',
      requestedStart: Timestamp.fromDate(new Date('2025-12-05T15:00:00Z')),
      requestedEnd: Timestamp.fromDate(new Date('2025-12-05T17:30:00Z')),
      durationMinutes: 150,
      confirmedStart: null,
      confirmedEnd: null,
      approval: {
        requiresStudioApproval: true,
        requiresEngineerApproval: true,
        resolvedBy: null,
        resolvedAt: null
      },
      updatedAt: Timestamp.now()
    }, { merge: true }));
    console.log('Artist can request reschedule');
  } catch (err) {
    console.error('Artist reschedule failed', err);
  }

  try {
    await assertSucceeds(artistDb.doc(`bookings/${bookingId}`).set({
      status: 'cancelled',
      approval: {
        requiresStudioApproval: false,
        requiresEngineerApproval: false,
        resolvedBy: artistId,
        resolvedAt: Timestamp.now()
      },
      updatedAt: Timestamp.now()
    }, { merge: true }));
    console.log('Artist can cancel booking');
  } catch (err) {
    console.error('Artist cancel failed', err);
  }

  try {
    await assertSucceeds(engineerDb.doc(`users/${engineerId}/media/media-001`).set({
      title: 'Mix Preview',
      caption: 'Test upload',
      format: 'audio',
      category: 'mix',
      mediaURL: 'https://example.com/audio.mp3',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now()
    }));
    console.log('Engineer can create own media document');
  } catch (err) {
    console.error('Engineer media create failed', err);
  }

  try {
    await assertFails(artistDb.doc(`users/${engineerId}/media/media-001`).set({
      title: 'Unauthorized edit'
    }, { merge: true }));
    console.log('Artist cannot edit engineer media document');
  } catch (err) {
    console.error('Unauthorized media write unexpectedly succeeded', err);
  }

  await env.cleanup();
})();
