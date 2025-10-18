const admin = require('firebase-admin');
const fetch = require('node-fetch');

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS');
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const API_KEY = 'AIzaSyAtAyVXXJPjqvgbHs_q6gI-owOHNO9lWz4';
const USER_UID = '4HQF6tiY0pRqnvmmbl3fnpCLTQ73'; // engineer account
const PROJECT_ID = 'punch-in-1f62f';

async function getIdToken() {
  const customToken = await admin.auth().createCustomToken(USER_UID);
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}` , {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(`Failed to exchange custom token: ${JSON.stringify(data)}`);
  }
  return data.idToken;
}

async function queryFirestore(idToken) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`;
  const body = {
    structuredQuery: {
      from: [{ collectionId: 'media', allDescendants: true }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            { fieldFilter: { field: { fieldPath: 'isRadioEligible' }, op: 'EQUAL', value: { booleanValue: true } } },
            { fieldFilter: { field: { fieldPath: 'isShared' }, op: 'EQUAL', value: { booleanValue: true } } },
            { fieldFilter: { field: { fieldPath: 'format' }, op: 'EQUAL', value: { stringValue: 'audio' } } },
          ],
        },
      },
      limit: 1,
    },
  };

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify(body),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Firestore query failed: ${res.status} ${text}`);
  }
  console.log('Query response:', text);
}

(async () => {
  try {
    const idToken = await getIdToken();
    console.log('Obtained ID token');
    await queryFirestore(idToken);
  } catch (err) {
    console.error(err);
  }
})();
