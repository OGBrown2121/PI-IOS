import functions from 'firebase-functions';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp();
const db = getFirestore();

const tokenize = (...values) =>
  Array.from(
    new Set(
      values
        .flatMap(value => (value || '').split(/\s+/))
        .map(token => token.trim().toLowerCase())
        .filter(Boolean),
    ),
  );

export const profileSearchTokens = functions
  .region('us-central1')
  .firestore.document('profiles/{userId}')
  .onWrite(async change => {
    const data = change.after.exists ? change.after.data() : null;
    if (!data) {
      return null;
    }

    const tokens = tokenize(
      data.displayName,
      data.username,
      data.profileDetails?.bio,
      data.profileDetails?.fieldOne,
      data.profileDetails?.fieldTwo,
    );

    return db.doc(change.after.ref.path).update({ searchTokens: tokens });
  });

export const studioSearchTokens = functions
  .region('us-central1')
  .firestore.document('studios/{studioId}')
  .onWrite(async change => {
    const data = change.after.exists ? change.after.data() : null;
    if (!data) {
      return null;
    }

    const tokens = tokenize(
      data.name,
      data.city,
      data.address,
      ...(data.amenities || []),
    );

    return db.doc(change.after.ref.path).update({ searchTokens: tokens });
  });
