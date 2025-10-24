const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const { Timestamp } = require('firebase/firestore');

const PROJECT_ID = 'punch-in-firestore-tests';

const minutesFrom = (timestamp, minutes) => {
  return Timestamp.fromMillis(timestamp.toMillis() + minutes * 60 * 1000);
};

const baseRequestData = () => {
  const now = Timestamp.now();
  return {
    videographerId: 'videographer123',
    requesterId: 'artist456',
    requesterDisplayName: 'TrapHouse T',
    requesterUsername: 'traphouse',
    startDate: now,
    durationMinutes: 120,
    shootLocations: ['Louisville'],
    projectDetails: 'Sample project details',
    quotedHourlyRate: 90,
    status: 'pending',
    createdAt: now,
    updatedAt: now
  };
};

(async () => {
  const rules = readFileSync('FirestoreRules.txt', 'utf8');
  const env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules }
  });

  const seedDocument = async (data) => {
    await env.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('videoProjectRequests').doc('request1').set(data);
    });
  };

  const seedDocumentWithoutQuote = async (data) => {
    const { quotedHourlyRate, ...rest } = data;
    await seedDocument(rest);
  };

  // Scenario 1: Videographer proposes new quote/time (allowed)
  await seedDocument(baseRequestData());

  const videographerDb = env.authenticatedContext('videographer123').firestore();
  const requestRef = videographerDb.collection('videoProjectRequests').doc('request1');

  const proposalTimestamp = Timestamp.now();
  const newStart = minutesFrom(proposalTimestamp, 90);

  try {
    await assertSucceeds(
      requestRef.set(
        {
          quotedHourlyRate: 120,
          status: 'awaitingRequesterDecision',
          requesterApprovedQuoteAt: null,
          decisionAt: null,
          decisionBy: null,
          updatedAt: proposalTimestamp,
          videographerRespondedAt: proposalTimestamp,
          startDate: newStart,
          durationMinutes: 150,
          shootLocations: ['Louisville', 'Lexington']
        },
        { merge: true }
      )
    );
    console.log('Scenario 1: quote update by videographer allowed');
  } catch (error) {
    console.error('Scenario 1 failed unexpectedly', error);
  }

  // Scenario 2: Videographer attempts to keep decision fields while quote is pending (should fail)
  await seedDocument({
    ...baseRequestData(),
    status: 'pending',
    decisionAt: Timestamp.now(),
    decisionBy: 'videographer123'
  });

  try {
    await assertFails(
      requestRef.set(
        {
          quotedHourlyRate: 130,
          status: 'awaitingRequesterDecision',
          requesterApprovedQuoteAt: null,
          decisionAt: Timestamp.now(),
          decisionBy: 'videographer123',
          updatedAt: Timestamp.now(),
          videographerRespondedAt: Timestamp.now()
        },
        { merge: true }
      )
    );
    console.log('Scenario 2: update rejected when decision metadata persists (expected)');
  } catch (error) {
    console.error('Scenario 2 succeeded unexpectedly', error);
  }

  // Scenario 3: Videographer accepts the request with required decision metadata (allowed)
  const responseTimestamp = Timestamp.now();
  await seedDocument({
    ...baseRequestData(),
    status: 'awaitingRequesterDecision',
    quotedHourlyRate: 140,
    startDate: minutesFrom(responseTimestamp, 120),
    durationMinutes: 180,
    updatedAt: responseTimestamp,
    videographerRespondedAt: responseTimestamp
  });

  const requesterDb = env.authenticatedContext('artist456').firestore();
  const requesterRef = requesterDb.collection('videoProjectRequests').doc('request1');
  try {
    await assertSucceeds(
      requesterRef.set(
        {
          status: 'scheduled',
          decisionAt: Timestamp.now(),
          decisionBy: 'artist456',
          updatedAt: Timestamp.now(),
          requesterApprovedQuoteAt: Timestamp.now()
        },
        { merge: true }
      )
    );
    console.log('Scenario 3: acceptance update allowed');
  } catch (error) {
    console.error('Scenario 3 failed unexpectedly', error);
  }

  // Scenario 4: Decline with no quoted rate (allowed)
  await seedDocument({
    ...baseRequestData(),
    status: 'pending',
    quotedHourlyRate: null
  });

  try {
    await assertSucceeds(
      requestRef.set(
        {
          status: 'declined',
          decisionAt: Timestamp.now(),
          decisionBy: 'videographer123',
          updatedAt: Timestamp.now(),
          requesterApprovedQuoteAt: null,
          videographerRespondedAt: Timestamp.now()
        },
        { merge: true }
      )
    );
    console.log('Scenario 4: decline without quote allowed');
  } catch (error) {
    console.error('Scenario 4 failed unexpectedly', error);
  }

  // Scenario 5: Add first quote when none existed (allowed)
  await seedDocumentWithoutQuote(baseRequestData());

  try {
    await assertSucceeds(
      requestRef.set(
        {
          quotedHourlyRate: 150,
          status: 'awaitingRequesterDecision',
          requesterApprovedQuoteAt: null,
          decisionAt: null,
          decisionBy: null,
          updatedAt: Timestamp.now(),
          videographerRespondedAt: Timestamp.now()
        },
        { merge: true }
      )
    );
    console.log('Scenario 5: first quote add allowed');
  } catch (error) {
    console.error('Scenario 5 failed unexpectedly', error);
  }

  // Scenario 6: Attach conversation to pending request (allowed)
  await seedDocument({
    ...baseRequestData(),
    status: 'pending'
  });

  try {
    await assertSucceeds(
      requestRef.set(
        {
          conversationId: 'conversation123',
          updatedAt: Timestamp.now()
        },
        { merge: true }
      )
    );
    console.log('Scenario 6: conversation attachment allowed');
  } catch (error) {
    console.error('Scenario 6 failed unexpectedly', error);
  }

  await env.cleanup();
})();
