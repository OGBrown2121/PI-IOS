import * as functions from 'firebase-functions/v1';
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

export const syncBookingAvailability = functions
  .region('us-central1')
  .firestore.document('bookings/{bookingId}')
  .onWrite(async (change, context) => {
    const bookingId = context.params.bookingId;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    if (!after) {
      if (before) {
        await removeBookingHolds(before, bookingId);
      }
      return null;
    }

    if (!before) {
      if (after.status === 'confirmed') {
        await ensureBookingHolds(after, bookingId);
      }
      return null;
    }

    const statusChanged = before.status !== after.status;
    const timesChanged =
      before.confirmedStart?.toMillis?.() !== after.confirmedStart?.toMillis?.() ||
      before.requestedStart.toMillis() !== after.requestedStart.toMillis() ||
      before.requestedEnd.toMillis() !== after.requestedEnd.toMillis();

    if (statusChanged || timesChanged) {
      if (after.status === 'confirmed') {
        await ensureBookingHolds(after, bookingId);
      } else if (['cancelled', 'completed'].includes(after.status)) {
        await removeBookingHolds(after, bookingId);
      }
    }

    return null;
  });

async function ensureBookingHolds(booking, bookingId) {
  const start = booking.confirmedStart ?? booking.requestedStart;
  const end = booking.confirmedEnd ?? booking.requestedEnd;
  const durationMinutes = booking.durationMinutes ?? Math.max(30, Math.round((end.toMillis() - start.toMillis()) / 60000));

  const studioEntry = {
    kind: 'bookingHold',
    ownerId: booking.studioId,
    studioId: booking.studioId,
    roomId: booking.roomId,
    engineerId: booking.engineerId,
    durationMinutes,
    startDate: start,
    endDate: end,
    sourceBookingId: bookingId,
    createdBy: booking.artistId,
    notes: 'Synced from booking',
    createdAt: booking.createdAt ?? new Date(),
    updatedAt: new Date(),
  };

  const engineerEntry = {
    kind: 'bookingHold',
    ownerId: booking.engineerId,
    studioId: booking.studioId,
    roomId: booking.roomId,
    engineerId: booking.engineerId,
    durationMinutes,
    startDate: start,
    endDate: end,
    sourceBookingId: bookingId,
    createdBy: booking.artistId,
    notes: 'Synced from booking',
    createdAt: booking.createdAt ?? new Date(),
    updatedAt: new Date(),
  };

  await Promise.all([
    db
      .collection('studioAvailability')
      .doc(booking.studioId)
      .collection('entries')
      .doc(bookingId)
      .set(studioEntry, { merge: true }),
    db
      .collection('engineerAvailability')
      .doc(booking.engineerId)
      .collection('entries')
      .doc(bookingId)
      .set(engineerEntry, { merge: true }),
  ]);
}

async function removeBookingHolds(booking, bookingId) {
  await Promise.all([
    db
      .collection('studioAvailability')
      .doc(booking.studioId)
      .collection('entries')
      .doc(bookingId)
      .delete()
      .catch(() => null),
    db
      .collection('engineerAvailability')
      .doc(booking.engineerId)
      .collection('entries')
      .doc(bookingId)
      .delete()
      .catch(() => null),
  ]);
}
