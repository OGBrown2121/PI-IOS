import * as functions from 'firebase-functions/v1';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';

initializeApp();
const db = getFirestore();

const ALERTS_COLLECTION = 'alerts';
const DATE_FORMAT_OPTIONS = {
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  timeZoneName: 'short',
};

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
  .firestore.document('users/{userId}')
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
        await Promise.all([
          removeBookingHolds(before, bookingId),
          sendBookingAlert(before, bookingId, 'cancelled'),
        ]);
      }
      return null;
    }

    if (!before) {
      await sendBookingAlert(after, bookingId, 'created');
      if (after.status === 'confirmed') {
        await ensureBookingHolds(after, bookingId);
      }
      return null;
    }

    if (!documentsEqual(before, after, ['status', 'requestedStart', 'requestedEnd', 'confirmedStart', 'confirmedEnd'])) {
      await sendBookingAlert(after, bookingId, 'updated');
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

export const notifyChatMessage = functions
  .region('us-central1')
  .firestore.document('conversations/{threadId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const threadId = context.params.threadId;
    if (!message) {
      return null;
    }

    const conversationSnap = await db.collection('conversations').doc(threadId).get();
    if (!conversationSnap.exists) {
      return null;
    }

    const conversation = conversationSnap.data() || {};
    const participantIds = resolveParticipantIds(conversation).filter(
      id => id && id !== message.senderId,
    );
    if (participantIds.length === 0) {
      return null;
    }

    const title = 'New message';
    const preview =
      message.content?.text ||
      message.lastMessagePreview ||
      conversation.displayName ||
      'You have a new message';

    await Promise.all(
      participantIds.map(participantId =>
        createAlert(participantId, {
          title,
          message: preview,
          category: 'chat',
          deeplink: `punchin://chat/${threadId}`,
        }),
      ),
    );
    return null;
  });

export const notifyMediaRating = functions
  .region('us-central1')
  .firestore.document('users/{ownerId}/media/{mediaId}/ratings/{ratingUserId}')
  .onWrite(async (change, context) => {
    const { ownerId, mediaId, ratingUserId } = context.params;
    const parentRef = db.collection('users').doc(ownerId).collection('media').doc(mediaId);

    if (!change.after.exists) {
      await parentRef.update({
        [`ratings.${ratingUserId}`]: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return null;
    }

    const ratingData = change.after.data() || {};
    const ratingValue = ratingData.rating;
    if (typeof ratingValue !== 'number') {
      return null;
    }

    await parentRef.set(
      {
        [`ratings.${ratingUserId}`]: ratingValue,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (ownerId === ratingUserId) {
      return null;
    }

    const [mediaSnap, reviewerSnap] = await Promise.all([
      parentRef.get(),
      db.collection('users').doc(ratingUserId).get(),
    ]);

    const media = mediaSnap.data() || {};
    const reviewer = reviewerSnap.data() || {};
    const displayTitle = media.title || media.displayCategoryTitle || 'Your media';
    const reviewerName = reviewer.displayName || reviewer.username || 'Someone';

    await createAlert(ownerId, {
      title: 'New rating received',
      message: `${reviewerName} rated "${displayTitle}"`,
      category: 'media',
      deeplink: `punchin://media/${mediaId}`,
    });
    return null;
  });

export const notifyBeatDownloadRequest = functions
  .region('us-central1')
  .firestore.document('beatDownloadRequests/{requestId}')
  .onCreate(async (snapshot) => {
    const request = snapshot.data();
    if (!request) {
      return null;
    }

    const { producerId, requesterId, beatId } = request;
    if (!producerId || producerId === requesterId) {
      return null;
    }

    const [beatSnap, requesterSnap] = await Promise.all([
      db.collection('users').doc(producerId).collection('beatCatalog').doc(beatId).get(),
      requesterId ? db.collection('users').doc(requesterId).get() : null,
    ]);

    const beat = beatSnap.exists ? beatSnap.data() || {} : {};
    const requester = requesterSnap?.exists ? requesterSnap.data() || {} : {};
    const beatTitle = beat.title || 'one of your beats';
    const requesterName = requester.displayName || requester.username || 'Someone';

    await createAlert(producerId, {
      title: 'Download request received',
      message: `${requesterName} requested files for "${beatTitle}".`,
      category: 'media',
      deeplink: null,
    });

    return null;
  });

export const notifyBeatDownloadDecision = functions
  .region('us-central1')
  .firestore.document('beatDownloadRequests/{requestId}')
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();

    if (!before || !after) {
      return null;
    }

    if (before.status === after.status) {
      return null;
    }

    const { requesterId, producerId, beatId, status } = after;
    if (!requesterId || requesterId === producerId) {
      return null;
    }

    const beatSnap = beatId
      ? await db.collection('users').doc(producerId).collection('beatCatalog').doc(beatId).get()
      : null;
    const beat = beatSnap?.exists ? beatSnap.data() || {} : {};
    const beatTitle = after.beatTitle || beat.title || 'your requested beat';

    const requesterRef = db
      .collection('users')
      .doc(requesterId)
      .collection('driveDownloadRequests')
      .doc(change.after.id);

    if (status === 'fulfilled') {
      await requesterRef.set(buildDrivePayload(after, beatTitle), { merge: true });

      await createAlert(requesterId, {
        title: 'Download ready',
        message: `Files for "${beatTitle}" are ready to download.`,
        category: 'media',
        deeplink: null,
      });
    } else if (status === 'rejected') {
      await requesterRef.set(buildDrivePayload(after, beatTitle), { merge: true });

      await createAlert(requesterId, {
        title: 'Download request declined',
        message: `The producer declined your request for "${beatTitle}".`,
        category: 'media',
        deeplink: null,
      });
    }

    return null;
  });

function buildDrivePayload(request, beatTitle) {
  const payload = {
    status: request.status,
    updatedAt: request.updatedAt ?? FieldValue.serverTimestamp(),
    producerId: request.producerId,
    requesterId: request.requesterId,
    beatId: request.beatId,
  };

  if (request.createdAt) {
    payload.createdAt = request.createdAt;
  }

  if (beatTitle) {
    payload.beatTitle = beatTitle;
  }

  if (request.status === 'fulfilled' && request.downloadURL) {
    payload.downloadURL = request.downloadURL;
  } else {
    payload.downloadURL = FieldValue.delete();
  }

  return payload;
}

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
      .collection('studios')
      .doc(booking.studioId)
      .collection('availability')
      .doc(bookingId)
      .set(studioEntry, { merge: true }),
    db
      .collection('users')
      .doc(booking.engineerId)
      .collection('availability')
      .doc(bookingId)
      .set(engineerEntry, { merge: true }),
  ]);
}

async function removeBookingHolds(booking, bookingId) {
  await Promise.all([
    db
      .collection('studios')
      .doc(booking.studioId)
      .collection('availability')
      .doc(bookingId)
      .delete()
      .catch(() => null),
    db
      .collection('users')
      .doc(booking.engineerId)
      .collection('availability')
      .doc(bookingId)
      .delete()
      .catch(() => null),
  ]);
}

async function sendBookingAlert(booking, bookingId, reason) {
  const titleMap = {
    created: 'New booking request',
    updated: 'Booking updated',
    cancelled: 'Booking cancelled',
  };
  const statusLabel = booking.status?.toString?.() || 'pending';
  const startDate = toDate(booking.confirmedStart || booking.requestedStart);
  const formattedDate = startDate
    ? startDate.toLocaleString('en-US', DATE_FORMAT_OPTIONS)
    : 'upcoming session';
  const message = `Session ${statusLabel} for ${formattedDate}`;
  const payload = {
    title: titleMap[reason] || 'Booking update',
    message,
    category: 'booking',
    deeplink: `punchin://bookings/${bookingId}`,
  };

  const recipients = new Set([booking.artistId, booking.engineerId].filter(Boolean));
  const studioOwnerId = await resolveStudioOwnerId(booking.studioId);
  if (studioOwnerId) {
    recipients.add(studioOwnerId);
  }

  await Promise.all(Array.from(recipients).map(userId => createAlert(userId, payload)));
}

async function resolveStudioOwnerId(studioId) {
  if (!studioId) {
    return null;
  }
  const studioSnap = await db.collection('studios').doc(studioId).get();
  return studioSnap.exists ? studioSnap.data()?.ownerId || null : null;
}

async function createAlert(userId, alert) {
  if (!userId) {
    return null;
  }
  const alertRef = db.collection('users').doc(userId).collection(ALERTS_COLLECTION).doc();
  return alertRef.set({
    title: alert.title,
    message: alert.message,
    category: alert.category,
    deeplink: alert.deeplink ?? null,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function toDate(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Date) {
    return value;
  }
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value.toDate) {
    try {
      return value.toDate();
    } catch {
      return null;
    }
  }
  return null;
}

function resolveParticipantIds(conversation) {
  if (Array.isArray(conversation.participantIds)) {
    return conversation.participantIds;
  }
  if (Array.isArray(conversation.participants)) {
    return conversation.participants
      .map(participant => participant?.id)
      .filter(Boolean);
  }
  if (conversation.participants && typeof conversation.participants === 'object') {
    return Object.keys(conversation.participants);
  }
  return [];
}

function documentsEqual(before, after, fields) {
  return fields.every(field => {
    const beforeValue = before[field];
    const afterValue = after[field];
    if (beforeValue?.toMillis && afterValue?.toMillis) {
      return beforeValue.toMillis() === afterValue.toMillis();
    }
    return JSON.stringify(beforeValue) === JSON.stringify(afterValue);
  });
}
