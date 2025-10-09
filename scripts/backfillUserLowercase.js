// scripts/backfillUserLowercase.js
const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

function loadServiceAccount() {
  const scriptDir = __dirname;
  const requested = process.argv[2] || process.env.FIREBASE_SERVICE_ACCOUNT || 'serviceAccountKey.json';
  const resolveCandidate = filePath =>
    path.isAbsolute(filePath) ? filePath : path.join(scriptDir, filePath);

  const tryRequire = filePath => {
    try {
      // Allow require to load absolute paths
      return require(filePath);
    } catch (err) {
      if (err.code === 'MODULE_NOT_FOUND') {
        return null;
      }
      throw err;
    }
  };

  const primaryPath = resolveCandidate(requested);
  const primaryAccount = tryRequire(primaryPath);
  if (primaryAccount) {
    return primaryAccount;
  }

  if (requested !== 'serviceAccountKey.json') {
    throw new Error(`Unable to load service account key from ${primaryPath}`);
  }

  const fallback = fs
    .readdirSync(scriptDir)
    .filter(name => name.endsWith('.json'))
    .map(name => resolveCandidate(name))
    .map(candidate => ({ candidate, account: tryRequire(candidate) }))
    .find(entry => entry.account && entry.candidate.includes('firebase-adminsdk'));

  if (!fallback) {
    throw new Error(
      `serviceAccountKey.json not found in ${scriptDir}. Pass a path via argv or set FIREBASE_SERVICE_ACCOUNT.`
    );
  }

  console.warn(`Loaded service account from ${fallback.candidate}`);
  return fallback.account;
}

const serviceAccount = loadServiceAccount();

initializeApp({
  credential: cert(serviceAccount)
});

const db = getFirestore();

async function main() {
  const snapshot = await db.collection('users').get();
  console.log(`Updating ${snapshot.size} users…`);

  const batchSize = 500; // stay under Firestore batch limit
  let batch = db.batch();
  let writes = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const username = (data.username || '').toString();
    const displayName = (data.displayName || '').toString();

    batch.update(doc.ref, {
      usernameLowercase: username.toLowerCase(),
      displayNameLowercase: displayName.toLowerCase()
    });

    writes += 1;
    if (writes === batchSize) {
      await batch.commit();
      console.log(`Committed ${writes} updates…`);
      batch = db.batch();
      writes = 0;
    }
  }

  if (writes > 0) {
    await batch.commit();
    console.log(`Committed final ${writes} updates.`);
  }

  console.log('Done.');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
