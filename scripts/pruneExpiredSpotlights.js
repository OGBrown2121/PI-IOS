// scripts/pruneExpiredSpotlights.js
const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

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

const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const ONE_YEAR_MS = 365 * ONE_DAY_MS;

function toDate(value) {
  if (!value) return null;
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (typeof value === 'number') {
    return new Date(value);
  }
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (value._seconds && value._nanoseconds) {
    return new Date(value._seconds * 1000 + value._nanoseconds / 1_000_000);
  }
  return null;
}

function sanitizeCallToAction(spotlight) {
  const copy = { ...spotlight };
  if (typeof copy.callToActionTitle === 'string' && copy.callToActionTitle.trim() === '' && copy.callToActionURL) {
    copy.callToActionTitle = 'Learn more';
  }
  return copy;
}

function isEventExpiredSoon(spotlight, nowMs) {
  const scheduled = toDate(spotlight.scheduledAt);
  if (!scheduled) return false;
  const expiryMs = scheduled.getTime() + ONE_DAY_MS;
  return expiryMs < nowMs;
}

function isRetainedAfterYear(spotlight, nowMs) {
  const scheduled = toDate(spotlight.scheduledAt);
  if (!scheduled) return true;
  return scheduled.getTime() >= nowMs - ONE_YEAR_MS;
}

function pruneCollection(items, nowMs) {
  if (!Array.isArray(items)) return [];
  return items
    .filter(item => item && typeof item === 'object')
    .map(sanitizeCallToAction)
    .filter(item => {
      const title = typeof item.title === 'string' ? item.title.trim() : '';
      if (!title) return false;
      if ((item.category || 'project') === 'event' && isEventExpiredSoon(item, nowMs)) {
        return false;
      }
      if (!isRetainedAfterYear(item, nowMs)) {
        return false;
      }
      return true;
    });
}

async function pruneUserProfiles() {
  const snapshot = await db.collection('users').get();
  console.log(`Scanning ${snapshot.size} user profiles for expired spotlight entries…`);
  const nowMs = Date.now();
  let updatedDocs = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const details = data.profileDetails || {};
    const originalProjects = details.upcomingProjects || [];
    const originalEvents = details.upcomingEvents || [];
    const prunedProjects = pruneCollection(originalProjects, nowMs);
    const prunedEvents = pruneCollection(originalEvents, nowMs);

    const needsUpdate =
      JSON.stringify(prunedProjects) !== JSON.stringify(originalProjects) ||
      JSON.stringify(prunedEvents) !== JSON.stringify(originalEvents);

    if (needsUpdate) {
      await doc.ref.update({
        'profileDetails.upcomingProjects': prunedProjects,
        'profileDetails.upcomingEvents': prunedEvents
      });
      updatedDocs += 1;
      console.log(`Pruned expired spotlight entries for user ${doc.id}`);
    }
  }

  console.log(`Completed pruning. Updated ${updatedDocs} profile document(s).`);
}

pruneUserProfiles().catch(err => {
  console.error(err);
  process.exit(1);
});
